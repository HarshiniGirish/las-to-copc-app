FROM condaforge/miniforge3:25.3.1-0

WORKDIR /app

COPY environment.yaml /tmp/environment.yaml
RUN conda env create -f /tmp/environment.yaml \
 && conda run -n copc Rscript -e "install.packages('lasR', repos = c('https://r-lidar.r-universe.dev', 'https://cloud.r-project.org'))" \
 && conda clean -afy

COPY las_to_copc_tiled.R /app/las_to_copc_tiled.R
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh /app/las_to_copc_tiled.R

ENV PATH=/opt/conda/envs/copc/bin:$PATH

ENTRYPOINT ["/app/run.sh"]
