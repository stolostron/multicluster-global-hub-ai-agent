# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Multicluster Global Hub ecosystem repositories.

---

## Multicluster Global Hub - Main Repository

Source: `repos/multicluster-global-hub/`

### Overview

Multicluster Global Hub is a Kubernetes operator-based system for managing ACM/OCM at very high scale. The repository contains three main components:

- **operator**: Deploys and manages the Global Hub infrastructure
- **manager**: Runs on the global hub cluster to sync data to/from PostgreSQL and Kafka
- **agent**: Runs on managed hub clusters to sync data between global hub and managed hubs

Shared code lives in `pkg/`.

### Architecture

#### Component Responsibilities

**Operator** (`operator/`):

- Deploys manager (global hub cluster) and agent (managed hub clusters)
- Manages CRD lifecycle and custom resources
- API definitions in `operator/api/`

**Manager** (`manager/`):

- `pkg/spec/`: Syncs resources FROM database TO managed hubs via Kafka
  - `specdb/`: Database operations for spec resources
  - `controllers/`: Watches and persists resources to database
  - `syncers/`: Retrieves from database and sends via transport
- `pkg/status/`: Syncs resource status FROM managed hubs TO database
  - `conflator/`: Merges bundles from transport before database insertion
  - `dispatcher/`: Routes bundles between transport, conflator, and database
  - `handlers/`: Persists transferred bundles to database
- `pkg/controllers/`: Common controllers (migration, backup)
- `pkg/processes/`: Periodic jobs (policy compliance cronjob, managed hub management)
- `pkg/restapis/`: REST APIs for managed clusters, policies, subscriptions
- `pkg/webhook/`: Webhooks for global resources

**Agent** (`agent/`):

- `pkg/spec/`: Applies resources FROM global hub TO managed hub cluster
  - `rbac/`: Role-based access control
  - `syncers/`: Syncs resources and signals from manager
  - `workers/`: Backend goroutines executing spec syncer tasks
- `pkg/status/`: Reports resource status FROM managed hub TO manager via Kafka/Inventory API
  - `filter/`: Deduplicates events
  - `generic/`: Templates for status syncers
    - `controller/`: Specifies resource types to sync
    - `handler/`: Updates bundles for watched resources
    - `emitter/`: Sends bundles via transport (CloudEvents)
    - `multi-event syncer`: Template for multiple events per object (policy syncer)
    - `multi-object syncer`: Template for one event per multiple objects (managedhub info syncer)
  - `syncers/`: Specific resource syncers using generic templates
- `pkg/controllers/inventory/`: Controllers reporting via Inventory API

**Shared** (`pkg/`):

- `transport/`: Kafka integration (Sarama and Confluent)
- `database/`: PostgreSQL operations (GORM and pgx)
- `bundle/`: Data bundling and compression
- `constants/`, `enum/`, `utils/`: Common utilities

### Build and Development Commands

#### Building Images

```bash
# Build and push all component images
make vendor
make build-operator-image push-operator-image IMG=<registry>/multicluster-global-hub-operator:<tag>
make build-manager-image push-manager-image IMG=<registry>/multicluster-global-hub-manager:<tag>
make build-agent-image push-agent-image IMG=<registry>/multicluster-global-hub-agent:<tag>

# Individual component builds
cd operator && make docker-build docker-push IMG=<registry>/multicluster-global-hub-operator:<tag>
cd manager && make
cd agent && make
```

#### Deploying

```bash
# Deploy operator to cluster
make deploy-operator  # or: cd operator && make deploy IMG=<registry>/...:tag

# Install Global Hub instance
kubectl apply -k operator/config/samples/

# Undeploy
make undeploy-operator  # or: cd operator && make undeploy
```

#### Code Quality

```bash
# Format code (standard Go formatting)
make fmt

# Strict formatting (gci + gofumpt)
make strict-fmt

# Update dependencies
make tidy
make vendor
```

#### Testing

**Unit Tests:**

```bash
# Run all unit tests (requires setup-envtest)
make unit-tests

# Run component-specific unit tests
make unit-tests-operator
make unit-tests-manager
make unit-tests-agent
make unit-tests-pkg
```

**Integration Tests:**

```bash
make integration-test                # All integration tests
make integration-test/operator
make integration-test/manager
make integration-test/agent
```

**E2E Tests:**

```bash
# Setup E2E environment (creates KinD clusters)
make e2e-setup

# Run specific E2E test suites
make e2e-test-cluster
make e2e-test-local-agent
make e2e-test-localpolicy
make e2e-test-grafana

# Run all E2E tests
make e2e-test-all

# Cleanup E2E environment
make e2e-cleanup

# E2E test with verbose output
make e2e-test-localpolicy VERBOSE=9
```

**Running Single Tests:**

To run a single test file or function:

```bash
# Unit test - single package
cd operator && KUBEBUILDER_ASSETS="$(setup-envtest use --use-env -p path)" go test -v ./pkg/path/to/package -run TestFunctionName

# Integration test - single test
KUBEBUILDER_ASSETS="$(setup-envtest use --use-env -p path)" go test -v ./test/integration/operator/... -run TestSpecificFunction
```

#### Operator-Specific Commands

When modifying operator API definitions:

```bash
cd operator
make generate    # Generate code (DeepCopy, etc.)
make manifests   # Generate CRDs, RBAC, etc.
make bundle      # Generate operator bundle
```

#### Logs

Fetch logs from E2E test environment:

```bash
make e2e-log/operator
make e2e-log/manager
make e2e-log/grafana
make e2e-log/agent
```

### Code Formatting Rules

The `make fmt` target enforces import dependency rules:

- `pkg/` must NOT import from `agent/`, `operator/`, or `manager/`
- `operator/` must NOT import from `agent/` or `manager/`
- `agent/` must NOT import from `manager/` or `operator/` (except `operator/api`)
- `manager/` must NOT import from `agent/` or `operator/` (except `operator/api`)

This maintains clean separation between components. Only shared code should live in `pkg/`.

### Testing Guidelines

- Integration tests use envtest and require KUBEBUILDER_ASSETS
- E2E tests create real KinD clusters (configured via MH_NUM, MC_NUM environment variables)
- Test scripts are in `test/script/`
- E2E test configuration is stored in a temporary `CONFIG_DIR`
- When debugging test failures, run tests individually with verbose flags (`-v` for go test, `VERBOSE=9` for E2E scripts)

### Key Dependencies

- **Kubernetes**: v0.33.x (client-go, api, apimachinery)
- **Controller Runtime**: v0.21.x
- **Kafka**: IBM Sarama v1.45.x, Confluent Kafka v2.12.x
- **Database**: GORM v1.30.x, pgx v5.7.x
- **CloudEvents**: v2.16.x
- **ACM/OCM**: Multiple stolostron and open-cluster-management.io dependencies
- **Go Version**: 1.25.7

### Environment Variables

E2E testing:

- `MH_NUM`: Number of managed hub clusters (default: 2)
- `MC_NUM`: Number of managed clusters (default: 1)
- `GH_NAMESPACE`: Global hub namespace (default: multicluster-global-hub)
- `VERBOSE`: Log verbosity level for E2E tests (default: 5)

Build:

- `REGISTRY`: Container registry (default: quay.io/stolostron)
- `IMAGE_TAG`: Image tag (default: latest)
- `GO_TEST`: Go test command override

---

## Multicluster Global Hub Operator Bundle

Source: `repos/multicluster-global-hub-operator-bundle/`

### Overview

This is a bundle repository for the multicluster global hub operator, part of the Red Hat Advanced Cluster Management (ACM) ecosystem. It packages Kubernetes operator manifests for distribution via Operator Lifecycle Manager (OLM).

### Repository Structure

- `bundle/` - Contains the operator bundle structure:
  - `manifests/` - Kubernetes manifests including ClusterServiceVersion (CSV), CRDs, and service definitions
  - `metadata/` - Bundle metadata including annotations.yaml
  - `tests/` - Scorecard test configuration for operator validation
- `.tekton/` - Tekton CI/CD pipeline definitions for automated builds
- `Containerfile.bundle` - Container build definition for the bundle image
- `konflux-patch.sh` - Script that patches manifests with production image references

### Build Process

#### Container Build
```bash
# Build the bundle container image
podman build -f Containerfile.bundle -t multicluster-global-hub-operator-bundle:latest .
```

#### Bundle Validation
```bash
# Run operator scorecard tests
operator-sdk scorecard bundle/
```

The build process involves:
1. Copying bundle manifests and metadata into a container
2. Running `konflux-patch.sh` to replace development image references with production registry URLs
3. The script updates the CSV with proper Red Hat registry images and versioning

### Key Components

#### ClusterServiceVersion (CSV)
- Main manifest: `bundle/manifests/multicluster-global-hub-operator.clusterserviceversion.yaml`
- Defines operator metadata, permissions, and deployment specifications
- Contains examples for MulticlusterGlobalHub, MulticlusterGlobalHubAgent, and ManagedClusterMigration CRDs

#### Custom Resource Definitions (CRDs)
- `operator.open-cluster-management.io_multiclusterglobalhubs.yaml` - Main hub configuration
- `operator.open-cluster-management.io_multiclusterglobalhubagents.yaml` - Agent configuration
- `global-hub.open-cluster-management.io_managedclustermigrations.yaml` - Migration operations

#### Image Management
The `konflux-patch.sh` script manages image references for:
- multicluster-global-hub-operator
- multicluster-global-hub-manager
- multicluster-global-hub-agent
- grafana
- postgres-exporter
- postgresql

### CI/CD Pipeline

#### Tekton Pipelines
- Push pipeline: `.tekton/multicluster-global-hub-operator-bundle-globalhub-1-6-push.yaml`
- Builds and publishes container images to `quay.io/redhat-user-workloads/`
- Uses the `konflux-build-catalog` pipeline templates

#### GitHub Actions
- `.github/workflows/labels.yml` - Automatically labels PRs from Konflux bot

### Branch Strategy
- Main development branch: `release-1.6`
- Version scheme follows semantic versioning aligned with the 1.6 release track

---

## Multicluster Global Hub Operator Catalog

Source: `repos/multicluster-global-hub-operator-catalog/`

### Overview

This repository contains the operator catalog for the Multicluster Global Hub operator, used for deploying and managing the Red Hat Advanced Cluster Management multicluster global hub across different OpenShift versions. The repository builds container images containing OLM (Operator Lifecycle Manager) catalogs for each supported OpenShift version.

### Architecture

#### Repository Structure

- **Version directories** (`v4.16/`, `v4.17/`, `v4.18/`, `v4.19/`, `v4.20/`): Each contains a `Containerfile.catalog` for building the catalog image for that specific OpenShift version
- **`configs/` submodule**: Git submodule pointing to the main operator catalog repository containing the actual catalog configurations
- **`filter_catalog.py`**: Python script that filters catalog.json to remove entries with schema "olm.package" and defaultChannel "release-1.5"
- **`catalog-template-current.json`**: Template containing the current catalog entry for release-1.6
- **`.tekton/`**: Contains Tekton pipeline configurations for CI/CD automation for each OpenShift version

#### Catalog Build Process

The catalog images are built using a multi-stage process:
1. Uses the OpenShift operator registry base image for the target version
2. Copies the catalog configuration from the `configs/` submodule
3. Runs `filter_catalog.py` to remove old release-1.5 entries
4. Appends new release-1.6 entries from `catalog-template-current.json`
5. Replaces development image references with production registry references
6. Pre-populates the OLM serve cache

#### CI/CD Pipeline

Each OpenShift version has dedicated Tekton pipelines:
- **Push pipelines**: Triggered on changes to version-specific paths when pushing to `release-1.6` branch
- **Pull request pipelines**: Triggered on PRs affecting the same paths
- Pipeline names follow pattern: `multicluster-global-hub-operator-catalog-v{version}-globalhub-1-6-{push|pull-request}.yaml`

### Development Commands

#### Building Catalog Images

Build catalog images using podman/docker with the version-specific Containerfiles:

```bash
# Build for specific OpenShift version (e.g., v4.18)
podman build -f v4.18/Containerfile.catalog -t catalog:v4.18 .
```

#### Working with Catalog Content

Filter catalog entries to remove old releases:
```bash
python3 filter_catalog.py path/to/catalog.json
```

#### Image Registry Management

The catalog references images from:
- **Development**: `quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/`
- **Production**: `registry.redhat.io/multicluster-globalhub/`

Image digest references in catalog-template-current.json should be updated when new operator bundle images are available.

### Key Files for Modifications

- **`catalog-template-current.json`**: Update when new operator bundles are released
- **Version-specific Containerfiles**: Modify when changing the build process for specific OpenShift versions
- **`.tekton/` pipeline files**: Update when changing CI/CD behavior or adding new OpenShift versions
- **`filter_catalog.py`**: Modify when changing catalog filtering logic

### Image Mirror Configuration

The deployment requires ImageDigestMirrorSet configurations to redirect from production registry URLs to development workload URLs. See README.md for complete mirror set examples for both global hub clusters and managed hub clusters.

---

## glo-grafana (Grafana for Global Hub)

Source: `repos/glo-grafana/`

### Overview

This is a customized fork of the Grafana project specifically tailored for Multicluster Global Hub. It provides the observability dashboard and visualization platform for monitoring global hub metrics stored in PostgreSQL.

### Repository Structure

- **`Containerfile.konflux`**: Multi-stage container build for Red Hat ecosystem
- **`stolostron-patches/`**: Custom patches applied to upstream Grafana
  - `0001-Forward-headers-from-auth-proxy-to-datasource.patch`: Enables auth proxy header forwarding
- **`.tekton/`**: Tekton CI/CD pipeline configurations for automated builds
- **Standard Grafana directories**: `pkg/`, `public/`, `apps/`, `conf/`, etc.

### Build Process

#### Container Build

The build uses a multi-stage process defined in `Containerfile.konflux`:

1. **Stage 1 - Builder**:
   - Base: `brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_1.25`
   - Applies custom patches from `stolostron-patches/`
   - Builds Grafana with strictfipsruntime tags
   - Produces platform-specific binaries

2. **Stage 2 - Final Image**:
   - Base: `registry.access.redhat.com/ubi9/ubi-minimal:latest`
   - Creates grafana user (UID/GID: 472)
   - Sets up directories for config, data, logs, plugins, provisioning
   - Exposes port 3000

```bash
# Build locally
podman build -f Containerfile.konflux -t glo-grafana:latest .
```

### Development Commands

#### Building from Source

```bash
# Install dependencies
make deps

# Build backend
go run build.go -build-tags=strictfipsruntime build

# Run Grafana
./bin/grafana server
```

#### Frontend Development

```bash
# Install node modules
yarn install

# Run frontend in watch mode
yarn start

# Build frontend
yarn build
```

### Custom Patches

**Auth Proxy Header Forwarding**: The stolostron patch enables forwarding authentication headers from the OpenShift OAuth proxy to datasources, allowing seamless integration with Red Hat SSO.

### CI/CD Pipeline

#### Tekton Pipelines

**Push Pipeline** (`.tekton/glo-grafana-globalhub-1-8-push.yaml`):
- Triggered on push to `release-1.8` branch
- Builds multi-platform images (linux/x86_64, ppc64le, s390x, arm64)
- Uses hermetic builds with prefetch for gomod dependencies
- Publishes to: `quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/glo-grafana-globalhub-1-8`
- Uses pipeline: `konflux-build-catalog/pipelines/common-base.yaml`

**Pull Request Pipeline** (`.tekton/glo-grafana-globalhub-1-8-pull-request.yaml`):
- Triggered on PRs to `release-1.8` branch
- Builds with 5-day expiration
- Same multi-platform build configuration

### Key Configuration

#### Environment Variables

Standard Grafana environment variables:
- `GF_PATHS_CONFIG`: `/etc/grafana/grafana.ini`
- `GF_PATHS_DATA`: `/var/lib/grafana`
- `GF_PATHS_HOME`: `/usr/share/grafana`
- `GF_PATHS_LOGS`: `/var/log/grafana`
- `GF_PATHS_PLUGINS`: `/var/lib/grafana/plugins`
- `GF_PATHS_PROVISIONING`: `/etc/grafana/provisioning`

#### Prefetch Dependencies

The build prefetches three gomod dependency sets:
- Main module: `.`
- Codegen: `pkg/codegen`
- Plugins codegen: `pkg/plugins/codegen`

### Container Labels

- **Component**: `multicluster-globalhub-grafana-rhel9`
- **CPE**: `cpe:/a:redhat:multicluster_globalhub:1.7::el9`
- **Version**: `release-1.7`
- **Maintainer**: `acm-component-maintainers@redhat.com`

### Branch Strategy

- Main development branch: `release-1.8`
- Based on upstream Grafana with ACM-specific customizations

---

## postgres_exporter (PostgreSQL Exporter)

Source: `repos/postgres_exporter/`

### Overview

This is a fork of the Prometheus Community's PostgreSQL Server Exporter, customized for Multicluster Global Hub. It exposes PostgreSQL metrics in Prometheus format for monitoring the global hub database.

### Repository Structure

- **`Containerfile.konflux`**: Multi-stage container build for Red Hat ecosystem
- **`cmd/postgres_exporter/`**: Main exporter code
- **`collector/`**: Metric collectors for various PostgreSQL subsystems
- **`config/`**: Configuration file examples and parsers
- **`postgres_mixin/`**: Grafana dashboards and alerts
- **`.tekton/`**: Tekton CI/CD pipeline configurations

### Build Process

#### Container Build

The build uses a two-stage process defined in `Containerfile.konflux`:

1. **Stage 1 - Builder**:
   - Base: `brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_1.25`
   - Builds `promu` build tool with CGO enabled
   - Uses promu to build postgres_exporter with CGO support

2. **Stage 2 - Final Image**:
   - Base: `registry.access.redhat.com/ubi9/ubi-minimal:latest`
   - Minimal image with only the exporter binary
   - Exposes port 9187
   - Runs as user `nobody`

```bash
# Build locally
podman build -f Containerfile.konflux -t postgres-exporter:latest .
```

### Development Commands

#### Building from Source

```bash
# Clone and build
git clone https://github.com/stolostron/postgres_exporter.git
cd postgres_exporter
make build

# Run exporter
./postgres_exporter <flags>
```

#### Using with Docker

```bash
# Start PostgreSQL test database
docker run --net=host -it --rm -e POSTGRES_PASSWORD=password postgres

# Run exporter
docker run \
  --net=host \
  -e DATA_SOURCE_NAME="postgresql://postgres:password@localhost:5432/postgres?sslmode=disable" \
  quay.io/prometheuscommunity/postgres-exporter
```

### Configuration

#### Configuration File

The exporter uses `postgres_exporter.yml` for configuration (specify with `--config.file`):

```yaml
auth_modules:
  module_name:
    type: userpass
    userpass:
      username: postgres_user
      password: postgres_password
    options:
      sslmode: disable
```

#### Environment Variables

- **`DATA_SOURCE_NAME`**: PostgreSQL connection DSN
  - Format: `postgresql://user:password@host:port/database?sslmode=disable`

### CI/CD Pipeline

#### Tekton Pipelines

**Push Pipeline** (`.tekton/postgres-exporter-globalhub-1-8-push.yaml`):
- Triggered on push to `release-1.8` branch
- Builds multi-platform images (linux/x86_64, ppc64le, s390x, arm64)
- Uses hermetic builds
- Publishes to: `quay.io/redhat-user-workloads/acm-multicluster-glo-tenant/postgres-exporter-globalhub-1-8`
- Uses pipeline: `konflux-build-catalog/pipelines/common-base.yaml`

**Pull Request Pipeline** (`.tekton/postgres-exporter-globalhub-1-8-pull-request.yaml`):
- Triggered on PRs to `release-1.8` branch
- Builds with 5-day expiration
- Same multi-platform build configuration

### Supported PostgreSQL Versions

CI-tested versions: `11`, `12`, `13`, `14`, `15`, `16`

### Key Features

#### Collector Flags

- `--collector.database`: Enable database collector (default: enabled)
- `--collector.database_wraparound`: Enable wraparound collector (default: disabled)
- Additional collectors for replication, locks, stat statements, etc.

#### Multi-Target Support (Beta)

Supports the multi-target pattern for scraping multiple PostgreSQL instances:

```yaml
scrape_configs:
  - job_name: 'postgres'
    static_configs:
      - targets:
        - server1:5432
        - server2:5432
    metrics_path: /probe
    params:
      auth_module: [module_name]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: 127.0.0.1:9187
```

### Container Labels

- **Component**: `multicluster-globalhub-postgres-exporter-rhel9-container`
- **CPE**: `cpe:/a:redhat:multicluster_globalhub:1.7::el9`
- **Version**: `release-1.7`
- **Maintainer**: `acm-component-maintainers@redhat.com`

### Integration with Global Hub

The postgres_exporter is deployed alongside the PostgreSQL database in the global hub cluster to provide:
- Database performance metrics
- Connection pool statistics
- Query execution metrics
- Replication lag monitoring
- Table and index statistics

### Branch Strategy

- Main development branch: `release-1.8`
- Based on upstream prometheus-community/postgres_exporter with ACM-specific build configuration
