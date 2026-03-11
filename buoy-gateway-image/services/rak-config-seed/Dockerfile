FROM alpine
RUN mkdir -p /seed
COPY local_conf.json global_conf.us915.sb1.json global_conf.us915.sb2.json seed.sh /seed/
RUN chmod +x /seed/seed.sh
CMD ["/seed/seed.sh"]
