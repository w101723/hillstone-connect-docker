Put these files in this directory before starting:

- `tls.crt` — TLS certificate for the noVNC HTTPS endpoint
- `tls.key` — matching private key
- `htpasswd` — nginx basic-auth file

Example for a private test environment:

```bash
openssl req -x509 -newkey rsa:3072 -nodes -days 365 \
  -keyout certs/tls.key -out certs/tls.crt -subj '/CN=hillstone-vpn.local'
docker run --rm httpd:2.4-alpine htpasswd -nbB admin 'replace-this-password' > certs/htpasswd
```

Do not commit real keys or password files.
