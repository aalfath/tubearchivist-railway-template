# Elasticsearch for the Tube Archivist Railway template.
# Official image, pinned by version and digest (multi-arch index; linux/amd64 is
# sha256:4a39707f1fee76c2386a5d681d7c5e0c8d663d2fe22382980297e765fdc11d0b).
# Tube Archivist v0.6.0 supports Elasticsearch 8 and 9; upstream recommends 9.5.5.
FROM elasticsearch:9.5.5@sha256:6f11b295d5099c18b8774d280a82725d1184d0d5cb08373b12785ce7cd7a9bfb

# Railway volumes are owned by root. The start script runs as root only to fix the
# volume's ownership, then runs Elasticsearch as its normal user (uid 1000).
USER 0
COPY --chmod=0755 start.sh /usr/local/bin/railway-start.sh
ENTRYPOINT ["/bin/tini", "-s", "--", "/usr/local/bin/railway-start.sh"]
