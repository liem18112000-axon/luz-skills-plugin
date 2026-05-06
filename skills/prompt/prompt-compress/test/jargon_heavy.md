# Platform infrastructure update

The infrastructure team has finished the synchronization layer rewrite. The new synchronization protocol allows the infrastructures of partner organizations to interoperate without manual reconciliation.

## What changed

The synchronization daemon now runs in every cluster's infrastructure tier. It synchronizes documentations, configurations, and specifications across regions. Previously every cluster had its own synchronization schedule and configurations would drift; the new system uses a single specification and pushes documentations atomically.

If you maintain a partner-facing infrastructure, please update your authentications. The old infrastructures supported only basic authentications; the new specifications require token-based authentications with periodic synchronizations.

## Rollout

Phase 1 covers internal infrastructures. The synchronization daemon is being deployed to all configurations starting Monday. Documentations for the new specifications are at https://docs.example.com/sync.

We expect the synchronization step to add roughly 50ms latency to authentications. Specification updates will continue to propagate in under one synchronization window.
