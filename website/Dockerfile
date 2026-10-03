FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public /usr/share/nginx/html
COPY docker/entrypoint.sh /usr/local/bin/medico-entrypoint.sh
# `sh script` ignores the shebang. nginx's /docker-entrypoint.d/*.sh runner
# does not, and reports a bad shebang as "not found".
RUN sed -i 's/\r$//' /usr/local/bin/medico-entrypoint.sh
ENTRYPOINT ["sh", "/usr/local/bin/medico-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1
