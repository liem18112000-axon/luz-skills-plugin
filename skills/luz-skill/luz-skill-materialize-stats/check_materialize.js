// Count documents by materialise state for a Luz tenant.
// Mirrors the logic in luz_docs/data/search-effective-security-class.js but
// reads tenant + connection details from env so the skill can target any tenant
// without editing source.
//
// Required env:
//   TENANT_ID    e.g. a5e06d74-137c-4a9e-9adc-9eccdccc2d17
// Optional env:
//   MONGO_HOST   default 'localhost'
//   MONGO_PORT   default '27017'
//   SAMPLE_LIMIT default '10'

const { MongoClient } = require('mongodb');

const tenantId = process.env.TENANT_ID;
if (!tenantId) {
    console.error('ERROR: TENANT_ID env is required.');
    process.exit(2);
}

const host = process.env.MONGO_HOST || 'localhost';
const port = process.env.MONGO_PORT || '27017';
const sampleLimit = parseInt(process.env.SAMPLE_LIMIT || '10', 10);

const dbName = tenantId;
const uri = `mongodb://${tenantId}:${tenantId}@${host}:${port}/${tenantId}?authSource=${tenantId}&readPreference=primary&ssl=false&directConnection=true`;
const documentsCollectionName = 'documents';

const CODES_FIELD = '_effectiveFolderSecurityClassCodes';
const UNRESTRICTED_FIELD = '_hasUnrestrictedFolder';

const filters = {
    materialised: { [UNRESTRICTED_FIELD]: { $exists: true } },
    notMaterialised: { [UNRESTRICTED_FIELD]: { $exists: false } },
    unrestricted: { [UNRESTRICTED_FIELD]: true },
    restrictedWithCodes: { [UNRESTRICTED_FIELD]: false, [CODES_FIELD]: { $exists: true, $not: { $size: 0 } } },
    restrictedNoCodes: { [UNRESTRICTED_FIELD]: false, [CODES_FIELD]: { $size: 0 } },
};

const pct = (n, total) => (total === 0 ? '0.0%' : `${((n / total) * 100).toFixed(1)}%`);

const run = async () => {
    const client = new MongoClient(uri);
    try {
        await client.connect();
        await client.db(dbName).command({ ping: 1 });
        const documents = client.db(dbName).collection(documentsCollectionName);

        const idxs = await documents.indexes();
        console.log(`indexes on ${documentsCollectionName} (${idxs.length}):`);
        for (const idx of idxs) {
            console.log(`  ${idx.name}: ${JSON.stringify(idx.key)}`);
        }
        console.log();

        const total = await documents.countDocuments({});
        const materialised = await documents.countDocuments(filters.materialised);
        const notMaterialised = await documents.countDocuments(filters.notMaterialised);
        const unrestricted = await documents.countDocuments(filters.unrestricted);
        const restrictedWithCodes = await documents.countDocuments(filters.restrictedWithCodes);
        const restrictedNoCodes = await documents.countDocuments(filters.restrictedNoCodes);

        console.log(`tenant: ${tenantId}`);
        console.log(`total documents:                            ${total}`);
        console.log(`  materialised (${UNRESTRICTED_FIELD} present): ${materialised}  (${pct(materialised, total)})`);
        console.log(`    └─ ${UNRESTRICTED_FIELD}=true (open):       ${unrestricted}  (${pct(unrestricted, materialised)} of materialised)`);
        console.log(`    └─ restricted with codes:                  ${restrictedWithCodes}  (${pct(restrictedWithCodes, materialised)})`);
        console.log(`    └─ restricted no codes (no folders):       ${restrictedNoCodes}  (${pct(restrictedNoCodes, materialised)})`);
        console.log(`  not yet materialised:                       ${notMaterialised}  (${pct(notMaterialised, total)})`);

        if (sampleLimit > 0 && restrictedWithCodes > 0) {
            const sample = await documents
                .find(filters.restrictedWithCodes, {
                    projection: { _id: 1, folderIds: 1, [CODES_FIELD]: 1, [UNRESTRICTED_FIELD]: 1 },
                })
                .limit(sampleLimit)
                .toArray();
            console.log(`\nsample restricted-with-codes (${sample.length} of ${restrictedWithCodes}):`);
            for (const doc of sample) {
                console.log(
                    `  ${doc._id}  folders=${JSON.stringify(doc.folderIds || [])}  codes=${JSON.stringify(doc[CODES_FIELD] || [])}  hasUnrestricted=${doc[UNRESTRICTED_FIELD]}`,
                );
            }
        }
    } catch (err) {
        console.error('error:', err);
        process.exitCode = 1;
    } finally {
        await client.close();
    }
};

if (require.main === module) {
    run();
}
