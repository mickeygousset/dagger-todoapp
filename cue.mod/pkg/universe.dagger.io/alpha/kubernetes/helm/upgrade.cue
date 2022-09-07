package helm

import (
	"strings"
	"list"

	"dagger.io/dagger"
	"universe.dagger.io/docker"
)

#Upgrade: {
	_base: #Image

	// The image to use when running the action.
	// Must contain the helm binary. Defaults to alpine/helm
	image: *_base.output | docker.#Image

	// Additional environment variables which are available in the
	// shell helm is executed in. Useful to set secrets
	env: [string]: string | dagger.#Secret

	// The kubeconfig file content
	kubeconfig: dagger.#Secret

	// Optionally mount a workspace, useful to read valuesfiles or a local chart
	workspace?: dagger.#FS

	// base settings

	// The name of the release
	name: string
	// The chart to use
	chart: string
	// Chart repository url where to locate the requested chart
	repo?: string
	// Specify a version constraint for the chart version to use.
	// This constraint can be a specific tag (e.g. 1.1.1) or it may reference a
	// Valid range (e.g. ^2.0.0). If this is not specified, the latest version is used
	version?: string
	// The kubernetes namespace
	namespace?: string

	// values

	// Specify values in a YAML file or a URL (can specify multiple)
	values: [...string]
	// Set values seperated by newline or comma. i.e.:
	// set: #"""
	//  global.image=daggerio/dagger
	//  podAnnotations.dagger\.io/action=enabled
	//  """#
	set?: string
	// set STRING values seperated by newline or comma (same as set)
	setString?: string

	// first class flags

	// Enable verbose output
	debug: *false | true

	// If set, upgrade process rolls back changes made in case of failed upgrade.
	// The --wait flag will be set automatically if --atomic is used
	atomic: *false | true
	// allow deletion of new resources created in this upgrade when upgrade fails
	cleanupOnFail: *false | true
	// Simulate an upgrade
	dryRun: *false | true
	// Force resource updates through a replacement strategy
	force: *false | true
	// If a release by this name doesn't already exist, run an install
	install: *false | true
	// Time to wait for any individual Kubernetes operation (like Jobs for hooks) (default 5m0s)
	timeout?: string
	// If set, will wait until all Pods, PVCs, Services, and minimum number of Pods of a Deployment,
	// StatefulSet, or ReplicaSet are in a ready state before marking the release as successful.
	// It will wait for as long as --timeout
	wait: *false | true

	// Chart repository username where to locate the requested chart
	username?: string
	// Chart repository password where to locate the requested chart
	password?: dagger.#Secret

	// Extra flags that are passed to the helm upgrade command. Use it
	// for anything that is not covered by the struct fields
	flags: [...string]

	run: docker.#Run & {
		// should probably run always since oftentimes
		// there a re no changes visible to dagger,
		// but a new release should be rolled out
		always: true
		input:  image
		if workspace != _|_ {
			workdir: "/workspace"
		}
		mounts: {
			"/root/.kube/config": {
				dest:     "/root/.kube/config"
				type:     "secret"
				contents: kubeconfig
			}
			if workspace != _|_ {
				"/workspace": {
					contents: workspace
					dest:     "/workspace"
				}
			}
		}
		_cmd:  strings.Join(
			list.Concat([
				[
					"helm",
					"upgrade",
					name,
					chart,
					if repo != _|_ {"--repo=\(repo)"},
					if version != _|_ {"--version=\(version)"},
					if namespace != _|_ {"--namespace=\(namespace)"},
					if install {"--install"},
					if install && namespace != _|_ {"--create-namespace"},
					if atomic {"--atomic"},
					if wait {"--wait"},
					if timeout != _|_ {"--timeout=\(timeout)"},
					for path in values {"--values=\(path)"},
					if set != _|_ {"--set=\(strings.Join(strings.Split(set, "\n"), ","))"},
					if setString != _|_ {"--set-string=\(strings.Join(strings.Split(setString, "\n"), ","))"},
					if debug {"--debug"},
					if dryRun {"--dry-run"},
					if force {"--force"},
					if cleanupOnFail {"--cleanup-on-fail"},
				],
				flags,
			]),
			" ")
		"env": env & {
			HELM_CHART: chart
			if password != _|_ {HELM_PASSWORD: password}
			if username != _|_ {HELM_USERNAME: username}
		}
		entrypoint: ["sh", "-c"]
		command: name: #"""
            # if there is no password, run the command
            if [ -z "$HELM_PASSWORD" ] || [ -z "$HELM_USERNAME" ]; then
                \#(_cmd)
                exit 0
            fi
            # otherwise check if we need to login to the registry or
            # pass the credentials to the command
            if [ "${HELM_CHART%%/*}" = "oci:" ]; then
                echo "$HELM_PASSWORD" | helm registry login "$(echo "$HELM_CHART" | cut -d/ -f3)" --username "$HELM_USERNAME" --password-stdin
                \#(_cmd)
            else
                \#(_cmd) --username "$HELM_USERNAME" --password "$HELM_PASSWORD"
            fi
            """#
	}
}
