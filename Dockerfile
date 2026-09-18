FROM alpine:3.20 AS certs
RUN apk add --no-cache openssl

# Self-signed CA + server cert for TLS. Fine for local/dev use - replace
# with certs from a real CA before running this anywhere untrusted.
#
# The CA cert needs basicConstraints/keyUsage v3 extensions - OpenSSL 3.x
# (and Python's ssl module) reject a CA with no keyUsage as untrusted for
# chain verification ("CA cert does not include key usage extension").
# The server cert gets a subjectAltName too, since modern TLS clients
# ignore the CN for hostname matching (RFC 6125) - DNS:postgres covers
# in-cluster Service DNS names (postgres, postgres.<namespace>, ...).
RUN mkdir -p /certs && cd /certs && \
    openssl genrsa -out ca.key 4096 && \
    openssl req -x509 -new -nodes -sha256 -days 3650 -key ca.key -out ca.crt -subj "/CN=postgres-dev-ca" \
      -addext "basicConstraints=critical,CA:TRUE" \
      -addext "keyUsage=critical,keyCertSign,cRLSign" && \
    openssl genrsa -out server.key 2048 && \
    openssl req -new -sha256 -key server.key -out server.csr -subj "/CN=postgres" \
      -addext "subjectAltName=DNS:postgres,DNS:localhost,IP:127.0.0.1" && \
    openssl x509 -req -sha256 -days 3650 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt \
      -copy_extensions copy && \
    rm -f server.csr ca.key ca.srl && \
    chmod 600 server.key

FROM postgres:16-bookworm
LABEL org.opencontainers.image.authors="Jerrico Gamis <jecklgamis@gmail.com>"

COPY --from=certs --chown=postgres:postgres /certs /certs
COPY pg_hba.conf /etc/postgresql-custom/pg_hba.conf

# Subdirectory, not the mount point itself - a freshly mounted volume can
# contain a lost+found dir that makes initdb think PGDATA isn't empty.
ENV PGDATA=/var/lib/postgresql/data/pgdata

# POSTGRES_PASSWORD is required by the base image's entrypoint; it refuses
# to start without one (or an explicit POSTGRES_HOST_AUTH_METHOD).
CMD ["postgres", \
     "-c", "ssl=on", \
     "-c", "ssl_cert_file=/certs/server.crt", \
     "-c", "ssl_key_file=/certs/server.key", \
     "-c", "ssl_ca_file=/certs/ca.crt", \
     "-c", "hba_file=/etc/postgresql-custom/pg_hba.conf"]
