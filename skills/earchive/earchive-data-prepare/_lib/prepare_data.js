// earchive-data-prepare core. Two roles:
//   MODE=probe    — try a single insert+drop on a namespaced probe collection;
//                   exit 0 on primary, exit 2 on secondary, exit 1 on error.
//   (default)     — assumes already on primary, then truncate + regenerate.

const { MongoClient, ObjectId } = require('mongodb');

const tenantId           = process.env.TENANT_ID || 'a5e06d74-137c-4a9e-9adc-9eccdccc2d17';
const docCount           = parseInt(process.env.DOC_COUNT || '128000', 10);
const folderCount        = parseInt(process.env.FOLDER_COUNT || '30', 10);
const maxNested          = Math.max(1, parseInt(process.env.MAX_NESTED || '3', 10));
const maxFoldersPerDoc   = Math.max(1, parseInt(process.env.MAX_FOLDERS_PER_DOC || '10', 10));
const batchSize          = Math.max(100, parseInt(process.env.BATCH_SIZE || '1000', 10));
const port               = process.env.PORT || '27017';
const mode               = process.env.MODE || 'generate';

const PROBE_COLLECTION   = '_earchive_data_prepare_probe';

const uri = `mongodb://${tenantId}:${tenantId}@localhost:${port}/${tenantId}`
    + `?authSource=${tenantId}&readPreference=primary&ssl=false&directConnection=true`;

const randInt    = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
const pickRandom = (arr) => arr[Math.floor(Math.random() * arr.length)];

async function probe(db) {
    const probeId = new ObjectId();
    try {
        await db.collection(PROBE_COLLECTION).insertOne({ _id: probeId, ts: new Date() });
        await db.collection(PROBE_COLLECTION).drop().catch(() => {});
        return { primary: true };
    } catch (err) {
        const code = err && err.code;
        const msg = err && err.message ? err.message : String(err);
        // 10107 = NotWritablePrimary, 13435 = NotMasterNoSlaveOk, 11602 = InterruptedDueToReplStateChange
        const isSecondary = code === 10107 || code === 13435 || /not\s*master|not\s*writable\s*primary/i.test(msg);
        return { primary: false, isSecondary, code, msg };
    }
}

function buildFolderTree(count, maxDepth) {
    const folders = [];
    const ids = Array.from({ length: count }, () => new ObjectId());
    const depth = new Array(count).fill(0);
    const rootCount = Math.max(1, Math.ceil(count / Math.pow(2, maxDepth)));

    for (let i = 0; i < count; i++) {
        if (i < rootCount) {
            folders.push({
                _id: ids[i],
                name: `folder-${i}`,
                parentFolderId: null,
                depth: 0,
                securityClassCode: [],
                inheritedSecurityClassCode: [],
            });
        } else {
            // Pick a parent from earlier folders that's still below maxDepth-1.
            const candidates = [];
            for (let j = 0; j < i; j++) {
                if (depth[j] < maxDepth - 1) candidates.push(j);
            }
            const parentIdx = candidates.length > 0 ? pickRandom(candidates) : 0;
            depth[i] = depth[parentIdx] + 1;
            folders.push({
                _id: ids[i],
                name: `folder-${i}`,
                parentFolderId: ids[parentIdx],
                depth: depth[i],
                securityClassCode: [],
                inheritedSecurityClassCode: [],
            });
        }
    }
    return folders;
}

async function generate(db) {
    if (process.env.CONFIRM !== 'yes') {
        console.error('[prepare] refusing to run — destructive op.');
        console.error(`[prepare] would truncate folders + documents and generate ${folderCount} folders + ${docCount} documents on tenant ${tenantId}.`);
        console.error('[prepare] re-run with CONFIRM=yes to proceed.');
        process.exitCode = 1;
        return;
    }

    console.log(`[prepare] tenant: ${tenantId}`);
    console.log(`[prepare] sizing: docs=${docCount} folders=${folderCount} maxNested=${maxNested} maxFoldersPerDoc=${maxFoldersPerDoc} batch=${batchSize}`);

    const before = {
        folders:   await db.collection('folders').estimatedDocumentCount(),
        documents: await db.collection('documents').estimatedDocumentCount(),
    };
    console.log(`[prepare] pre-truncate: folders=${before.folders} documents=${before.documents}`);

    const t0 = Date.now();
    await db.collection('folders').deleteMany({});
    await db.collection('documents').deleteMany({});
    console.log(`[prepare] truncated in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

    const folders = buildFolderTree(folderCount, maxNested);
    if (folders.length > 0) {
        await db.collection('folders').insertMany(folders, { ordered: false });
    }
    console.log(`[prepare] folders inserted: ${folders.length}`);

    // folderIds on documents are stored as 24-char hex strings (matches data/index.js
    // and the `folderIds: <string-id>` query convention used by luz-docs).
    const folderHexIds = folders.map((f) => f._id.toString());
    const now = new Date();
    let inserted = 0;
    const t1 = Date.now();
    while (inserted < docCount) {
        const toGen = Math.min(batchSize, docCount - inserted);
        const batch = new Array(toGen);
        for (let i = 0; i < toGen; i++) {
            const numFolders = randInt(1, Math.min(maxFoldersPerDoc, folderHexIds.length));
            const docFolders = new Set();
            while (docFolders.size < numFolders) docFolders.add(pickRandom(folderHexIds));
            batch[i] = {
                _id: new ObjectId(),
                folderIds: Array.from(docFolders),
                _updatedDate: now,
                _deletionStatus: 'false',
                name: `doc-${inserted + i}`,
            };
        }
        await db.collection('documents').insertMany(batch, { ordered: false });
        inserted += toGen;
        if (inserted % (batchSize * 10) === 0 || inserted === docCount) {
            const elapsed = ((Date.now() - t1) / 1000).toFixed(1);
            const rate = (inserted / Math.max(0.1, (Date.now() - t1) / 1000)).toFixed(0);
            console.log(`[prepare]   documents inserted: ${inserted}/${docCount}  elapsed=${elapsed}s  rate=${rate}/s`);
        }
    }

    const after = {
        folders:   await db.collection('folders').estimatedDocumentCount(),
        documents: await db.collection('documents').estimatedDocumentCount(),
    };
    console.log(`[prepare] post-generate: folders=${after.folders} documents=${after.documents}`);
    console.log(`[prepare] total elapsed: ${((Date.now() - t0) / 1000).toFixed(1)}s`);
}

async function main() {
    const client = new MongoClient(uri, { serverSelectionTimeoutMS: 7000 });
    try {
        await client.connect();
        const db = client.db(tenantId);

        const result = await probe(db);
        if (!result.primary) {
            if (result.isSecondary) {
                console.log(`[probe] not-primary (code=${result.code || ''})`);
                process.exitCode = 2;
                return;
            }
            console.error(`[probe] error: ${result.msg}`);
            process.exitCode = 1;
            return;
        }
        console.log('[probe] write-ok — primary confirmed');

        if (mode === 'probe') return;

        await generate(db);
    } catch (err) {
        console.error('[prepare] fatal:', err.message || err);
        process.exitCode = 1;
    } finally {
        await client.close();
    }
}

main();
