FROM condaforge/miniforge3:25.3.1-0

WORKDIR /app

COPY environment.yaml /tmp/environment.yaml
RUN conda env create -f /tmp/environment.yaml \
 && conda clean -afy

COPY las_to_copc_tiled.py /app/las_to_copc_tiled.py
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

# Put env on PATH so run.sh can call python/pdal directly
ENV PATH=/opt/conda/envs/copc/bin:$PATH

ENTRYPOINT ["/app/run.sh"]
