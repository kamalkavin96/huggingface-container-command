FROM minio/minio:latest

ENV MINIO_ROOT_USER=admin
ENV MINIO_ROOT_PASSWORD=admin

EXPOSE 7860

# Huggingface space bucket mounted as volumne /data
CMD ["server","/data","--address",":7860"]
