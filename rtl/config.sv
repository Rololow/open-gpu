package config_pkg;
    // Global configuration parameters
    parameter int MEM_WORDS = 65536;
    parameter bit DEBUG = 1;
    // Depth of simple DMA pipeline (number of outstanding reads to allow)
    // Increase to 4 to stress FIFO pairing and throughput
    parameter int DMA_PIPELINE_DEPTH = 4;
endpackage : config_pkg
