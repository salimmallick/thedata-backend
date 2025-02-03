#!/bin/bash

# Exit on error
set -e

CERT_DIR="config/certs"
mkdir -p $CERT_DIR

# Generate CA key and certificate
openssl genrsa -out $CERT_DIR/ca-key.pem 4096
openssl req -new -x509 -days 365 -key $CERT_DIR/ca-key.pem -out $CERT_DIR/ca.pem -subj "/CN=thedata.io CA"

# Function to generate service certificates
generate_service_cert() {
    SERVICE=$1
    openssl genrsa -out $CERT_DIR/$SERVICE-key.pem 2048
    openssl req -new -key $CERT_DIR/$SERVICE-key.pem -out $CERT_DIR/$SERVICE.csr -subj "/CN=$SERVICE.thedata.io"
    openssl x509 -req -days 365 -in $CERT_DIR/$SERVICE.csr -CA $CERT_DIR/ca.pem -CAkey $CERT_DIR/ca-key.pem -CAcreateserial -out $CERT_DIR/$SERVICE-cert.pem
    rm $CERT_DIR/$SERVICE.csr
}

# Generate certificates for each service
for service in nats questdb clickhouse grafana api; do
    echo "Generating certificates for $service..."
    generate_service_cert $service
done

# Copy certificates to service directories
mkdir -p config/nats/certs
cp $CERT_DIR/nats-* config/nats/certs/
cp $CERT_DIR/ca.pem config/nats/certs/

mkdir -p config/questdb/certs
cp $CERT_DIR/questdb-* config/questdb/certs/
cp $CERT_DIR/ca.pem config/questdb/certs/

mkdir -p config/clickhouse/certs
cp $CERT_DIR/clickhouse-* config/clickhouse/certs/
cp $CERT_DIR/ca.pem config/clickhouse/certs/

echo "Certificate generation complete!" 