# Tube Archivist for the Railway template.
# Official image, pinned by version and digest (multi-arch index; linux/amd64 is
# sha256:9d3da6982d9a9e3213d447db56cec346225ab26716459494a786a225a7edf05c).
FROM bbilly1/tubearchivist:v0.6.0@sha256:0cbc18aa953c72ec7dfdd6f8fa7c2fe89b5d04489857d7baa354fecbd6181e69

# Upstream's run.sh starts 4 web workers and 4 Celery workers and backgrounds them,
# so a crashed worker never stops the container. Our start script runs the same
# setup steps with worker counts sized for small Railway plans, and exits non-zero
# when any process dies so Railway's ON_FAILURE policy restarts the service.
COPY --chmod=0755 start.sh /app/railway-start.sh

WORKDIR /app
ENTRYPOINT ["/bin/tini", "--"]
CMD ["/app/railway-start.sh"]
