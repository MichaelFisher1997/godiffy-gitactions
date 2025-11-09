import fs from 'node:fs/promises';
import path from 'node:path';
import fsSync from 'node:fs';

function getInput(name, { required = false, defaultValue } = {}) {
  const key = `INPUT_${name.replace(/ /g, '_').toUpperCase()}`;
  const val = process.env[key];
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
  console.log(`::set-output name=${name}::${lineValue}`);
  if (process.env.GITHUB_OUTPUT) {
    try {
      fsSync.appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${lineValue}\n`);
    } catch {
      // ignore
    }
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
    const res = await fetch(url, {
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

  const res = await fetch(url, {
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

  const res = await fetch(url, {
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
  const apiKey = getInput('api-key', { required: true });
  const siteId = getInput('site-id', { required: true });
  const imagesPath = getInput('images-path', { required: true });
  const baseUrl = getInput('base-url', { required: true });
  const baselineBranch = getInput('baseline-branch', { defaultValue: 'master' });
  const baselineCommitInput = getInput('baseline-commit', { defaultValue: 'latest' });
  const createReportInput = getInput('create-report', { defaultValue: 'false' });
  const algorithm = getInput('algorithm', { defaultValue: 'pixelmatch' });
  const threshold = getInput('threshold', { defaultValue: '0.9' });

  const candidateBranch = process.env.GITHUB_HEAD_REF || process.env.GITHUB_REF_NAME || '';
  const candidateCommit = process.env.GITHUB_SHA || '';
  const eventName = process.env.GITHUB_EVENT_NAME || '';

  logInfo('Starting GoDiffy action...');

  // Upload candidate images
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
    return;
  }

  const shouldCreateReport = String(createReportInput).toLowerCase() === 'true';

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

  if (comparisonResults.failedComparisons > 0) {
    logWarn(`${comparisonResults.failedComparisons} comparisons failed (average similarity: ${comparisonResults.averageSimilarity}%)`);
  } else {
    logInfo(`All comparisons passed (average similarity: ${comparisonResults.averageSimilarity}%)`);
  }
}

main().catch((err) => {
  logError(err && err.message ? err.message : String(err));
  process.exit(1);
});