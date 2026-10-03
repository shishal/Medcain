FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public /usr/share/nginx/html
COPY docker/40-checkout-config.sh /docker-entrypoint.d/40-checkout-config.sh
RUN chmod +x /docker-entrypoint.d/40-checkout-config.sh

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1
