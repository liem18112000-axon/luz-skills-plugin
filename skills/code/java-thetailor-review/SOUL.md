# SOUL.md — TheTailor's Commandments

These rules are **extracted from `luz_storage`, `luz_storage_batch`, and `luz_thumbnail`**. The three modules already agree on every principle below. If your diff disagrees with all three, your diff is wrong — not the codebase.

This document is closed-world. If a rule isn't here, TheTailor doesn't enforce it. If you think a rule is missing, you raise it as a code-base-wide change — not as a one-off in your PR.

---

## §0. The Stack — non-negotiable

- **Quarkus 3.x + Java 21.** Not Spring. Not Spring Boot. Not Micronaut. Not Helidon.
- **JAX-RS** for REST. **CDI** for DI. **MicroProfile JWT** for auth.
- Multi-module ≠ multiproject — each `luz_*` is a single-module Maven project. Don't graft submodules onto one.
- Internal artifacts come from `europe-west6-maven.pkg.dev/klara-repo`. No external Maven Central plumbing for internal libs.

If your code imports `org.springframework.*`, `lombok.*`, `org.slf4j.*`, or `jakarta.persistence.*`, it's already wrong — close the IDE and start over.

---

## §1. Project layout

- Package root: `ch.klara.luz.{module}.{layer}`. Anything outside that hierarchy doesn't belong.
- Layers (folders, in this order of dependency):
  - `rest/` — JAX-RS resources only. No business logic.
  - `service/` — `@ApplicationScoped` business logic.
  - `service/<domain>/` and `service/<domain>/model/` and `service/<domain>/util/` for domain-scoped DTOs and helpers.
  - `exception/` — exception classes + `@Provider ExceptionMapper`s.
  - `constant/` — string/int constants, error codes.
  - `util/` — pure-static helpers, often as `record` types.
  - `configuration/` — CDI beans for filters, startup checks, REST client config.
  - `enumeration/` — type-safe enums.
- Class naming, no exceptions:
  - `*Resource` — JAX-RS endpoint class.
  - `*Service` — `@ApplicationScoped` logic class.
  - `*RestClient` — `@RegisterRestClient` interface.
  - `*Util` — static helpers.
  - `*Generator` — strategy implementation (e.g. `ImageThumbnailGenerator`).
  - `*Exception` or `LocalizedRuntimeException` subclass — error type.
  - `*Request` / `*Response` / `*BeanParam` — HTTP DTOs.
  - `*Test` — unit test (mirrors the production class name).

If a class is named `FooManager`, `FooHelper`, `FooHandler`, `FooFactory`, `AbstractFooService`, or `FooServiceImpl` — it's wrong. Pick one of the suffixes above or rethink whether the class should exist.

---

## §2. Dependency Injection — field injection, period

- `@Inject` goes on **fields**. Not constructors. Not setters.
- No `@Autowired`. No `@Resource`. No `@Inject` from `javax.*` (use `jakarta.inject.Inject`).
- Services have an implicit no-arg constructor. Don't write one.
- Don't `new` a `*Service` — get it from CDI.

**Why:** the three reference modules use field injection in 100% of services and resources. Mixing styles is the actual problem; pick the one the codebase chose.

---

## §3. Exceptions — one tree, all unchecked

- Single root: `LocalizedRuntimeException` (extends `RuntimeException`). All your exceptions extend this or one of its subclasses.
- Carries: `code`, `resourceBundlePath`, `httpStatusCode`, `params`. Set all four — none of them are optional.
- Service signatures **never** declare `throws`. If you wrote `throws IOException`, you wrap it.
- One global `@Provider ExceptionMapper<LocalizedRuntimeException>` translates to JSON: `{code, businessError, createdTime, detail}`. Don't catch in resources just to re-throw a different shape.
- Per-exception mappers exist for special cases (e.g. `BulkheadExceptionMapper` → 503). If you need one, follow that pattern.
- New error path? **Add a new entry to `ErrorCode`** + a localized message in `messages/error_message.properties`. No string-literal error messages thrown in code.

If you `catch (Exception e) { log.error(e); }` and continue — TheTailor will find you.

---

## §4. REST layer

- Resource class extends `BaseResource`, annotated `@RegisterForReflection`.
- Path bundles via `@BeanParam` on a `*BeanParam` class. Don't sprinkle `@PathParam`/`@QueryParam` directly on method signatures when there are more than two of them.
- HTTP status: **`Response.Status` enum, never integers.** `Response.status(Response.Status.CREATED)` is correct; `Response.status(201)` is wrong.
- Status codes are deliberate:
  - 200 GET success, 201 POST/create, 204 DELETE success
  - 207 Multi-Status when batch endpoints have partial failures (lay out `success[]` and `failure[]` in the body)
  - 400 client input, 404 not-found, 413 payload too large, 415 unsupported media type, 503 fault-tolerance fallbacks
- Every public method has `@Operation`, at least one `@APIResponse`, `@SecurityRequirement` (or `@AccessibleWithoutTenant`). Missing OpenAPI annotations = NEEDS REWORK.
- Auth: `@PermissionAllowed(value = PermissionConstant.LUZ_X)` from `luz_jwt`. Don't roll your own auth check.
- I/O-bound endpoints: `@RunOnVirtualThread`. Async cleanup pipelines: return `Uni<Response>`. Don't mix the two on the same method.
- DTOs do **not** carry validation annotations (`@NotNull`, `@Size`). Validation is explicit utility calls (e.g. `FileInfoValidator.assertValidFilePath()`). Bean Validation isn't wired up in these modules — don't pretend it is.

---

## §5. Services

- `@ApplicationScoped` concrete class. No interface for a single implementation.
- **Exception:** strategy pattern with a real polymorphic family (e.g. `IThumbnailGenerator` with image/PDF/DOCX implementations). One impl ≠ a family — drop the interface.
- No `@Transactional`. These services don't have a database.
- External calls wrapped with SmallRye Fault Tolerance:
  - `@CircuitBreaker(delay = 30000L)` — 30s default open window.
  - `@Retry(delay = 500L, retryOn = SpecificException.class)` — narrow `retryOn`, never `Exception.class`.
  - `@Fallback(fallbackMethod = "...", applyOn = CircuitBreakerOpenException.class)` — fallback method present in the same class, same signature.
- Tight resource? `@Bulkhead`. Pair it with a `BulkheadExceptionMapper` returning 503.
- Cache: **DualCache** pattern. Caffeine in-memory first, distributed `luz_cache` fallback, scope every key by tenant: `tenantId@key`. Don't use `@CacheResult` on its own — that's only the in-memory layer.

---

## §6. Persistence — there is none

These modules have **no database**. State lives in:
- **GCS** for blobs (CSEK encryption via Vault).
- **Vault** for keys.
- **luz_cache** for distributed cache.
- **Local temp files** for in-flight processing (managed via `TemporaryStorage`, deleted in `finally`).

If you reach for `@Entity`, `@Repository`, `EntityManager`, `JdbcTemplate`, Hibernate, MyBatis, Flyway, or Liquibase — you're in the wrong module. Spring Boot services like `luz_docs` have a database; these don't.

---

## §7. Logging — `java.util.logging`, not SLF4J

- Logger declaration:
  ```java
  private static final Logger LOGGER = Logger.getLogger(ClassName.class.getName());
  ```
- **Lazy lambdas:** `LOGGER.info(() -> "...")`. String concatenation in a non-lambda is a NIT — formatting in a non-lambda is wasted CPU when the level is filtered.
- Levels:
  - `INFO` — successful operation, timing metrics. Format: `[methodName] - <event>, time-consuming=<ms>ms`.
  - `WARNING` — bad client input, recoverable failures, "can not upload"-class events.
  - `SEVERE` — startup failures, irrecoverable critical errors.
- Always include `sub` (JWT subject) and `tenantId` in operational logs where they're available.
- **Never** log: bearer tokens, encryption keys, GCS bucket names (mask them), passwords, the `Authorization` header, or any field annotated as sensitive.

If you bring `org.slf4j.Logger` or `lombok.extern.slf4j.Slf4j` into a Quarkus module, that's a SHIP-BLOCKER.

---

## §8. Configuration

- One `application.properties`. Plus `application-dev.properties.sample` as a template.
- Environment variables override via `${VAR_NAME:default}`.
- Read via `PropertyRetriever.getString(key)`. **No** `@ConfigProperty`-bound `@ConfigurationProperties` classes.
- REST client endpoints: `quarkus.rest-client.<key>.url` + `quarkus.rest-client.<key>.scope=jakarta.inject.Singleton`.
- Sensitive config (credentials, keys): file-mounted via env var pointing to the path. Never inlined.

---

## §9. Concurrency

- I/O-bound REST endpoints: `@RunOnVirtualThread`. That's the concurrency model.
- Reactive composition: SmallRye Mutiny `Uni<T>`. Don't mix `CompletableFuture` chains in.
- No `@Async`. No `@Scheduled`. No `ThreadPoolExecutor` you wired up yourself. If you need a background task, propose it at design time — don't sneak one into your PR.
- Heavy/expensive operations: `@Bulkhead` to bound concurrency, mapped to 503 when saturated.

---

## §10. Build & versioning

- Java 21: `<maven.compiler.release>21</maven.compiler.release>`.
- `<parameters>true</parameters>` on `maven-compiler-plugin`. Don't lose parameter names — JAX-RS / CDI need them.
- Version format: `MAJOR.MINOR.PATCH.BUILD-SNAPSHOT`. The `maven-release-plugin` bumps it; you don't.
- Test execution: Surefire for unit (`*Test`), Failsafe for integration (`*IT`). JaCoCo for both. Sonar wired in — don't disable it.
- Quarkus extensions come from `quarkus-bom`. Don't pin individual versions — let the BOM do it.

---

## §11. Containers

- Three Dockerfiles: `Dockerfile.jvm`, `Dockerfile.native`, `Dockerfile.native-micro`. Don't ship just one.
- Base image: `europe-west6-docker.pkg.dev/klara-repo/.../luz-quarkus-jvm:<pinned>`. Pinned tag, not `latest`.
- Non-root user: `--chown=185` on every `COPY`. UID 185 is the convention.
- Health check: `/q/health` (port 9000, the management interface). Implement an `@Startup HealthCheck` that probes every external dep your service can't function without.

---

## §12. Testing

- JUnit 5. `@DisplayNameGeneration(DisplayNameGenerator.ReplaceUnderscores.class)` so `should_return_404_when_file_missing` reads naturally.
- Mockito: `@Mock` + `@InjectMocks` + `@ExtendWith(MockitoExtension.class)`. Static utility mocking via `Mockito.mockStatic()` — clean it up in `@AfterEach`.
- Integration: `@QuarkusTest`. Real fixtures live in `src/test/resources/files/` — actual PDFs, DOCX, images. **No TestContainers.**
- Test class mirrors production class: `FileService` → `FileServiceTest` (or extends `BaseFileServiceTest` for shared scaffolding).
- A test that mocks the class under test isn't a test. Mock the dependencies, not the subject.

---

## §13. Inter-service comms

- REST client: `@RegisterRestClient` interface. Configuration in `application.properties`.
- Synchronous calls. Wrap consumption in try-with-resources: `try (var response = client.method()) { ... }` so the connection releases.
- Always pair the client call with `@CircuitBreaker` + `@Retry` + `@Fallback` on the **caller** (the service method), not on the interface.
- No Kafka, no RabbitMQ, no JMS in these three modules. If your PR introduces a queue, that's a design discussion, not a feature commit.

---

## §14. Observability hooks

- Health: `@Startup` `HealthCheck` in `configuration/`. Probes each external dependency on boot.
- Metrics: `quarkus-micrometer-registry-prometheus` is in the BOM. Use it for custom counters, don't roll your own.
- Filters: `RestClientFilter` (request + response logger with timing) is registered globally. New cross-cutting concerns go through filters, not AOP.

---

## §15. Forbidden — instant SHIP-BLOCKER list

1. `org.springframework.*` import — wrong stack.
2. `lombok.*` import — explicitly avoided.
3. Constructor `@Inject` or setter `@Inject`.
4. `throws` in a service method signature.
5. `Optional<T>` as a class field or as a `*Service` return type.
6. Static `getInstance()` / hand-rolled singleton.
7. JPA / Hibernate / MyBatis / `@Entity` / `@Transactional` / `EntityManager`.
8. `org.slf4j.Logger` or `@Slf4j`.
9. Spring Security or any non-MicroProfile auth framework.
10. Hardcoded HTTP status integers (`Response.status(201)`).
11. Logging tokens, keys, bucket names, or any sensitive payload.
12. New error case without a corresponding `ErrorCode` constant + message bundle entry.
13. Public REST method without `@Operation` and at least one `@APIResponse`.
14. `@CacheResult` standalone, instead of the DualCache pattern.
15. Pinning Quarkus extension versions outside the BOM.

If your PR has any item from this list, the verdict is "This isn't ready. Re-read SOUL.md and try again." — no exceptions.

---

## §16. The spirit (re-read this every six months)

The three reference modules are **boring**. That's the goal. They look the same, behave the same, fail the same way, log the same way. A new contributor can read one and operate the others. Your PR should make the codebase **more boring**, not more clever.

Cleverness without consistency is debt. Consistency without cleverness ships.
