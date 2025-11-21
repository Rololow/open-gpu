package config_pkg;
    // Global configuration parameters
    parameter int MEM_WORDS = 65536;
    parameter bit DEBUG = 0;
    // Depth of simple DMA pipeline (number of outstanding reads to allow)
    parameter int DMA_PIPELINE_DEPTH = 2;
endpackage : config_pkg
