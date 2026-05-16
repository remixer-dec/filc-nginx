FROM nginx:latest AS nginx-user
FROM gcr.io/distroless/base-debian13

COPY --from=nginx-user /etc/passwd /etc/passwd
COPY --from=nginx-user /etc/group /etc/group

COPY --from=nginx-user /etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=nginx-user /lib/x86_64-linux-gnu/libnss_files.so.2 /lib/x86_64-linux-gnu/libnss_files.so.2

COPY . /usr/local/filc-nginx

ENV LD_LIBRARY_PATH=/usr/local/filc-nginx/lib

CMD ["/usr/local/filc-nginx/nginx", "-p", "/usr/local/filc-nginx/", "-c", "/etc/nginx/nginx.conf", "-e", "/var/log/nginx/error.log", "-g", "daemon off;"]
