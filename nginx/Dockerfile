FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY blue.conf /etc/nginx/conf.d/default.conf

# Nginx runs without root because the lab router listens on unprivileged port 8080.
RUN chown -R nginx:nginx /etc/nginx/conf.d
USER nginx
EXPOSE 8080
