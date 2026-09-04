# Fixture for the shared-build-publish-image self-test. Not published.
#
# Deliberately trivial and deliberately digest-pinned: the point is to exercise
# the workflow's build, smoke, scan and tag wiring, not to test Alpine.
FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
RUN echo "selftest" > /selftest
LABEL org.opencontainers.image.title="ci-templates selftest fixture"
