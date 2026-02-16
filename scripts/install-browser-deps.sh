#!/usr/bin/env bash
echo "All browser dependencies are now baked into the Docker image."
echo "This script is no longer needed. See Dockerfile stages: base -> runtimes -> browser-deps -> dependencies -> final"
exit 0
