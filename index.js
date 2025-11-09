import fs from 'node:fs/promises';
import path from 'node:path';
import fsSync from 'node:fs';

function getInput(name, { required = false, defaultValue } = {}) {
  // GitHub Actions preserves hyphens in input names, so we need to check both formats
  const keyWithHyphen = `INPUT_${name.toUpperCase()}`;
  const keyWithUnderscore = `INPUT_${name.replace(/-/g, '_').replace(/ /g, '_').toUpperCase()}`;
  
  const val = process.env[keyWithHyphen] || process.env[keyWithUnderscore];
  
  if ((val === undefined || val === '') && required && defaultValue === undefined) {
    logError(`Input "${name}" is required but was not provided.`);
    process.exit(1);
  }
  return val !== undefined && val !== '' ? val : defaultValue;
}

function logInfo(msg) {
  console.log(msg);
}

function logWarn(msg) {
  console.warn(`::warning::${msg}`);
}

function logError(msg) {
  console.error(`::error::${msg}`);
}

function setOutput(name, value) {
  if (value === undefined || value === null) return;
  const lineValue = String(value);
  
  // Use new GITHUB_OUTPUT file format (deprecated: ::set-output)
  if (process.env.GITHUB_OUTPUT) {
    try {
      fsSync.appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${lineValue}\n`);
    } catch (err) {
      logWarn(`Failed to write output ${name}: ${err.message}`);
    }
  } else {
    // Fallback for older runners
    console.log(`::set-output name=${name}::${lineValue}`);
  }
}

async function* walkFiles(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walkFiles(full);
    } else if (entry.isFile()) {
      yield full;
    }
  }
}

async function fetchWithRetry(url, options, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const res = await fetch(url, options);
      
      // Retry on 502/503/504 (server errors that might be cold starts)
      if (attempt < maxRetries && (res.status === 502 || res.status === 503 || res.status === 504)) {
        const delay = Math.min(1000 * Math.pow(2, attempt - 1), 5000); // Exponential backoff: 1s, 2s, 4s
        logWarn(`Server returned ${res.status}, retrying in ${delay}ms (attempt ${attempt}/${maxRetries})...`);
        await new Promise(resolve => setTimeout(resolve, delay));
        continue;
      }
      
      return res;
    } catch (err) {
      if (attempt < maxRetries) {
        const delay = Math.min(1000 * Math.pow(2, attempt - 1), 5000);
        logWarn(`Request failed: ${err.message}, retrying in ${delay}ms (attempt ${attempt}/${maxRetries})...`);
        await new Promise(resolve => setTimeout(resolve, delay));
        continue;
      }
      throw err;
    }
  }
}

async function captureScreenshots({ configPath, branch }) {
  logInfo(`Reading configuration from ${configPath}...`);
  
  // Dynamically import playwright only when needed
  let chromium;
  try {
    const playwright = await import('playwright');
    chromium = playwright.chromium;
  } catch (err) {
    logError(`Failed to import playwright: ${err.message}. Make sure dependencies are installed.`);
    process.exit(1);
  }
  
  let config;
  try {
    const configContent = await fs.readFile(configPath, 'utf-8');
    config = JSON.parse(configContent);
  } catch (err) {
    logError(`Failed to read or parse ${configPath}: ${err.message}`);
    process.exit(1);
  }

  // Determine base URL for current branch
  const baseUrl = config.baseUrls?.[branch] || config.baseUrls?.['master'] || config.baseUrl;
  if (!baseUrl) {
    logError('No baseUrl configured in godiffy.json');
    process.exit(1);
  }

  const pages = config.pages || [];
  if (!pages.length) {
    logWarn('No pages configured in godiffy.json');
    return;
  }

  const screenshotsDir = config.screenshotsDir || './screenshots';
  const viewport = config.viewport || { width: 1280, height: 720 };

  // Clean and recreate screenshots directory
  try {
    await fs.rm(screenshotsDir, { recursive: true, force: true });
  } catch (err) {
    // Ignore if directory doesn't exist
  }
  await fs.mkdir(screenshotsDir, { recursive: true });

  logInfo(`Capturing ${pages.length} screenshots from ${baseUrl}...`);

  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport,
  });
  const page = await context.newPage();

  try {
    for (const pageConfig of pages) {
      const url = `${baseUrl}${pageConfig.path}`;
      const screenshotName = `${pageConfig.name}.png`;
      const screenshotPath = path.join(screenshotsDir, screenshotName);

      logInfo(`Capturing ${url}...`);
      
      try {
        await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
        await page.screenshot({ path: screenshotPath, fullPage: true });
        logInfo(`✓ Saved ${screenshotName}`);
      } catch (err) {
        logError(`Failed to capture ${url}: ${err.message}`);
        process.exit(1);
      }
    }
  } finally {
    await browser.close();
  }

  logInfo(`Successfully captured ${pages.length} screenshots to ${screenshotsDir}`);
}

async function uploadScreenshots({ baseUrl, apiKey, siteId, imagesPath, branch, commit }) {
  const successful = [];

  try {
    await fs.access(imagesPath);
  } catch {
    logWarn(`Images path "${imagesPath}" does not exist; nothing to upload.`);
    return successful;
  }

  for await (const filePath of walkFiles(imagesPath)) {
    const ext = path.extname(filePath).toLowerCase();
    if (!['.png', '.jpg', '.jpeg'].includes(ext)) continue;

    const objectKey = path.relative(imagesPath, filePath).replace(/\\/g, '/');
    const fileData = await fs.readFile(filePath);
    const base64Data = fileData.toString('base64');

    const contentType = ext === '.png' ? 'image/png' : 'image/jpeg';

    const url = new URL('/api/v2/uploads', baseUrl);
    const res = await fetchWithRetry(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        siteId: siteId,
        branch: branch,
        commit: commit,
        path: objectKey,
        fileName: path.basename(filePath),
        contentType: contentType,
        data: base64Data,
      }),
    });

    const bodyText = await res.text();
    let body;
    try {
      body = bodyText ? JSON.parse(bodyText) : {};
    } catch {
      body = {};
    }

    if (!res.ok) {
      const err = (body && body.error) || `status ${res.status}`;
      logError(`Failed to upload ${objectKey}: ${err}`);
      process.exit(1);
    }

    if (!body || !body.upload || !body.upload.id) {
      logWarn(`Upload response missing expected fields for ${objectKey}; got: ${bodyText}`);
      continue;
    }

    successful.push({
      id: body.upload.id,
      objectKey: body.upload.objectKey,
      branch,
      commit,
    });

    logInfo(`Uploaded ${objectKey} (id=${body.upload.id})`);
  }

  logInfo(`Total successful uploads: ${successful.length}`);
  return successful;
}

async function resolveBaselineCommit({ baseUrl, apiKey, siteId, baselineBranch, baselineCommit }) {
  if (baselineCommit !== 'latest') return baselineCommit;

  const url = new URL('/api/v2/uploads', baseUrl);
  url.searchParams.set('siteId', siteId);
  url.searchParams.set('limit', '1000'); // Get more results to ensure we find baseline uploads

  const res = await fetchWithRetry(url, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });

  const body = await res.json().catch(() => null);

  if (!res.ok) {
    const msg = body && body.error ? body.error : `HTTP ${res.status}`;
    logError(`Failed to fetch baseline uploads for latest commit: ${msg}`);
    process.exit(1);
  }

  if (!Array.isArray(body)) {
    logWarn('Baseline uploads response is not an array; skipping report generation.');
    return null;
  }

  const candidates = body
    .filter((u) => u.branch === baselineBranch && u.commit && u.createdAt)
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

  const latest = candidates[0];
  if (!latest) {
    logWarn(
      `No baseline uploads found for site ${siteId} on branch ${baselineBranch} when resolving latest baseline commit; skipping report.`,
    );
    return null;
  }

  logInfo(`Resolved baseline commit for ${baselineBranch} to ${latest.commit}`);
  return latest.commit;
}

async function runComparisons({
  baseUrl,
  apiKey,
  siteId,
  baselineBranch,
  baselineCommit,
  candidateBranch,
  candidateCommit,
  saveReport,
  algorithm,
  threshold,
}) {
  const url = new URL(`/api/v2/sites/${siteId}/compare`, baseUrl);

  const payload = {
    baselineBranch,
    baselineCommit,
    candidateBranch,
    candidateCommit,
    algorithm: algorithm || 'pixelmatch',
    threshold: Number(threshold || 0.9),
    saveReport: Boolean(saveReport),
  };

  if (saveReport) {
    payload.reportName = `PR Visual Report: ${candidateBranch} vs ${baselineBranch}`;
    payload.reportDescription = `Visual regression report for ${candidateBranch} (${candidateCommit}) vs ${baselineBranch} (${baselineCommit}).`;
  }

  const res = await fetchWithRetry(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  const bodyText = await res.text();
  let body;
  try {
    body = bodyText ? JSON.parse(bodyText) : {};
  } catch {
    body = {};
  }

  if (!res.ok) {
    const msg = (body && body.error) || `HTTP ${res.status}`;
    logError(`Failed to run comparisons: ${msg}`);
    process.exit(1);
  }

  logInfo('Comparisons completed successfully.');
  return body;
}

async function main() {
  // Debug: Log all INPUT_ environment variables
  logInfo('=== DEBUG: Environment Variables ===');
  Object.keys(process.env)
    .filter(key => key.startsWith('INPUT_'))
    .forEach(key => {
      const value = process.env[key];
      const displayValue = key === 'INPUT_API_KEY' ? '[REDACTED]' : value;
      logInfo(`${key}=${displayValue}`);
    });
  logInfo('=== END DEBUG ===');

  const apiKey = getInput('api-key', { required: true });
  const siteId = getInput('site-id', { required: true });
  let imagesPath = getInput('images-path');
  const captureScreenshotsInput = getInput('capture-screenshots', { defaultValue: 'false' });
  const configPath = getInput('config-path', { defaultValue: './godiffy.json' });
  const baseUrl = getInput('base-url', { required: true });
  const baselineBranch = getInput('baseline-branch', { defaultValue: 'master' });
  const baselineCommitInput = getInput('baseline-commit', { defaultValue: 'latest' });
  const createReportInput = getInput('create-report', { defaultValue: 'false' });
  let algorithm = getInput('algorithm', { defaultValue: 'pixelmatch' });
  let threshold = getInput('threshold', { defaultValue: '0.9' });
  
  // Read config file to get algorithm and threshold if not provided as inputs
  let config = null;
  try {
    const configContent = await fs.readFile(configPath, 'utf-8');
    config = JSON.parse(configContent);
    
    // Use config values if inputs weren't explicitly provided
    if (!getInput('algorithm') && config.algorithm) {
      algorithm = config.algorithm;
    }
    if (!getInput('threshold') && config.threshold !== undefined) {
      threshold = String(config.threshold / 100); // Convert percentage to decimal
    }
  } catch (err) {
    // Config file not found or invalid, use defaults
  }

  const candidateBranch = process.env.GITHUB_HEAD_REF || process.env.GITHUB_REF_NAME || '';
  const eventName = process.env.GITHUB_EVENT_NAME || '';
  
  // For PRs, use the actual HEAD SHA of the PR branch, not the merge commit
  let candidateCommit = process.env.GITHUB_SHA || '';
  if (eventName === 'pull_request' && process.env.GITHUB_EVENT_PATH) {
    try {
      const eventData = JSON.parse(await fs.readFile(process.env.GITHUB_EVENT_PATH, 'utf-8'));
      if (eventData.pull_request?.head?.sha) {
        candidateCommit = eventData.pull_request.head.sha;
        logInfo(`Using PR head commit: ${candidateCommit}`);
      }
    } catch (err) {
      logWarn(`Could not read PR head SHA from event, using GITHUB_SHA: ${err.message}`);
    }
  }

  logInfo('Starting GoDiffy action v2...');

  const shouldCreateReport = String(createReportInput).toLowerCase() === 'true';
  const shouldCaptureScreenshots = String(captureScreenshotsInput).toLowerCase() === 'true';

  // Capture screenshots if requested
  if (shouldCaptureScreenshots) {
    await captureScreenshots({
      configPath,
      branch: candidateBranch,
    });
    
    // Use screenshots directory from config
    imagesPath = config?.screenshotsDir || './screenshots';
  }

  // Upload candidate images if path provided
  if (imagesPath) {
    const candidateUploads = await uploadScreenshots({
      baseUrl,
      apiKey,
      siteId,
      imagesPath,
      branch: candidateBranch,
      commit: candidateCommit,
    });

    if (!candidateUploads.length) {
      logWarn('No candidate uploads; nothing to compare.');
      if (!shouldCreateReport) {
        return;
      }
    }
  } else {
    logInfo('No images-path provided; skipping upload step.');
  }

  if (!shouldCreateReport) {
    logInfo('create-report is false; skipping comparison.');
    return;
  }

  if (eventName !== 'pull_request') {
    logInfo(`create-report is true but event is "${eventName}", not "pull_request"; skipping comparison.`);
    return;
  }

  // Resolve baseline commit
  const baselineCommit =
    baselineCommitInput === 'latest'
      ? await resolveBaselineCommit({
          baseUrl,
          apiKey,
          siteId,
          baselineBranch,
          baselineCommit: baselineCommitInput,
        })
      : baselineCommitInput;

  if (!baselineCommit) return;

  // Run comparisons using the backend's compare endpoint
  const comparisonResults = await runComparisons({
    baseUrl,
    apiKey,
    siteId,
    baselineBranch,
    baselineCommit,
    candidateBranch,
    candidateCommit,
    saveReport: shouldCreateReport,
    algorithm,
    threshold,
  });

  // Set outputs
  setOutput('total-comparisons', comparisonResults.totalComparisons || 0);
  setOutput('passed-comparisons', comparisonResults.passedComparisons || 0);
  setOutput('failed-comparisons', comparisonResults.failedComparisons || 0);
  setOutput('average-similarity', comparisonResults.averageSimilarity || 0);

  if (comparisonResults.reportId) {
    setOutput('report-id', comparisonResults.reportId);
    setOutput('report-url', `${baseUrl}/sites/${siteId}/reports/${comparisonResults.reportId}`);
  }

  // Check if results meet threshold
  const thresholdPercent = Number(threshold) * 100;
  const avgSimilarity = comparisonResults.averageSimilarity || 0;
  const meetsThreshold = avgSimilarity >= thresholdPercent;
  
  setOutput('threshold-met', meetsThreshold ? 'true' : 'false');

  if (comparisonResults.failedComparisons > 0) {
    logWarn(`${comparisonResults.failedComparisons} comparisons failed (average similarity: ${comparisonResults.averageSimilarity}%)`);
  } else {
    logInfo(`All comparisons passed (average similarity: ${comparisonResults.averageSimilarity}%)`);
  }

  // Fail the action if threshold not met
  if (!meetsThreshold) {
    logError(`Visual regression check failed: Average similarity ${avgSimilarity.toFixed(2)}% is below threshold of ${thresholdPercent}%`);
    process.exit(1);
  }
  
  logInfo(`✓ Visual regression check passed: ${avgSimilarity.toFixed(2)}% similarity (threshold: ${thresholdPercent}%)`);
}

main().catch((err) => {
  logError(err && err.message ? err.message : String(err));
  process.exit(1);
});