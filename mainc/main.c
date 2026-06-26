#include "sleep.h"
#include "xil_printf.h"
#include "xstatus.h"

#include "npu_csb_config.h"
#include "npu_test_vectors.h"

#define STARTUP_DELAY_US                1000000U

static npu_context_t g_npu;
static npu_layer_config_t g_layer;

int main(void)
{
    int status;

    status = npu_initialize_uart0();
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    npu_context_init(
        &g_npu,
        CSB_BASE,
        NPU_TEST_INPUT_BASE,
        NPU_TEST_WEIGHT_BASE,
        NPU_TEST_OUTPUT_BASE
    );

    xil_printf("\r\nNPU single-layer smoke test\r\n");
    xil_printf("UART0: MIO14 RX / MIO15 TX / 115200 8N1\r\n");
    npu_print_context(&g_npu);

    npu_layer_config_init(
        &g_layer,
        NPU_TEST_INPUT_WIDTH,
        NPU_TEST_INPUT_HEIGHT,
        NPU_TEST_INPUT_CHANNELS,
        NPU_TEST_KERNEL_WIDTH,
        NPU_TEST_KERNEL_HEIGHT,
        NPU_TEST_KERNEL_COUNT,
        NPU_TEST_STRIDE_X,
        NPU_TEST_STRIDE_Y
    );

    if (npu_layer_config_validate(&g_layer) != XST_SUCCESS) {
        xil_printf("NPU setup failed: invalid layer config.\r\n");
        return XST_FAILURE;
    }

    npu_print_layer_config(&g_layer);

    if ((NPU_TEST_INPUT_WORDS != g_layer.data_words) ||
        (NPU_TEST_WEIGHT_WORDS != g_layer.weight_words) ||
        (NPU_TEST_OUTPUT_WORDS != g_layer.output_words) ||
        (NPU_TEST_CSC_ATOMICS != g_layer.csc_atomics)) {
        xil_printf("NPU setup failed: generated header does not match layer config.\r\n");
        xil_printf("  header input/weight/output/atomics = %lu/%lu/%lu/%lu\r\n",
                   (unsigned long)NPU_TEST_INPUT_WORDS,
                   (unsigned long)NPU_TEST_WEIGHT_WORDS,
                   (unsigned long)NPU_TEST_OUTPUT_WORDS,
                   (unsigned long)NPU_TEST_CSC_ATOMICS);
        xil_printf("  config input/weight/output/atomics = %lu/%lu/%lu/%lu\r\n",
                   (unsigned long)g_layer.data_words,
                   (unsigned long)g_layer.weight_words,
                   (unsigned long)g_layer.output_words,
                   (unsigned long)g_layer.csc_atomics);
        return XST_FAILURE;
    }

    usleep(STARTUP_DELAY_US);

    xil_printf("Preparing DDR vectors from Vitis header...\r\n");
    npu_prepare_ddr_vectors(&g_npu,
                            npu_test_input_words,
                            NPU_TEST_INPUT_WORDS,
                            npu_test_weight_words,
                            NPU_TEST_WEIGHT_WORDS,
                            NPU_TEST_OUTPUT_WORDS);

    xil_printf("Programming CSB registers once for this layer...\r\n");
    npu_program_single_layer_registers(&g_npu, &g_layer);
    npu_print_status(&g_npu);

    status = npu_run_cdma_loads(&g_npu);
    if (status != XST_SUCCESS) {
        xil_printf("NPU smoke test FAILED during CDMA load.\r\n");
        while (1) {
            sleep(1);
        }
    }

    status = npu_run_compute_pipeline(&g_npu, &g_layer);
    if (status != XST_SUCCESS) {
        xil_printf("NPU smoke test FAILED during compute/writeback.\r\n");
        while (1) {
            sleep(1);
        }
    }

    xil_printf("Checking output DDR...\r\n");
    status = npu_compare_output_words(&g_npu,
                                      npu_test_expected_output_words,
                                      NPU_TEST_OUTPUT_WORDS);
    if (status != XST_SUCCESS) {
        xil_printf("NPU single-layer smoke test FAILED\r\n");
    } else {
        xil_printf("NPU single-layer smoke test PASSED\r\n");
    }

    while (1) {
        sleep(1);
    }

    return XST_SUCCESS;
}
