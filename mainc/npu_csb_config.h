#ifndef NPU_CSB_CONFIG_H
#define NPU_CSB_CONFIG_H

#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xil_types.h"
#include "xparameters.h"
#include "xuartps.h"

#if defined(__has_include)
#if __has_include("xil_cache.h")
#include "xil_cache.h"
#define NPU_HAS_XIL_CACHE               1
#endif
#endif

#ifndef NPU_HAS_XIL_CACHE
#define NPU_HAS_XIL_CACHE               0
#endif

#if defined(XPAR_APB_TOP_0_BASEADDR)
#define CSB_BASE                        XPAR_APB_TOP_0_BASEADDR
#define CSB_TARGET_NAME                 "APB_TOP"
#else
#define CSB_BASE                        0x43C00000U
#define CSB_TARGET_NAME                 "APB_TOP_FIXED"
#endif

#define CDMA_CONTROL                    0x00U
#define CDMA_STATUS                     0x04U
#define DATA_MATRIX_WIDTH               0x08U
#define DATA_MATRIX_HEIGHT              0x0CU
#define DATA_CHANNEL_COUNT              0x10U
#define DATA_DST_BASE                   0x14U
#define DATA_SRC_BASE_ADDR              0x18U
#define WEIGHT_MATRIX_WIDTH             0x1CU
#define WEIGHT_MATRIX_HEIGHT            0x20U
#define WEIGHT_CHANNEL_COUNT            0x24U
#define WEIGHT_DST_BASE                 0x28U
#define WEIGHT_SRC_BASE_ADDR            0x2CU
#define CSC_CONTROL                     0x30U
#define CSC_STATUS                      0x34U
#define CSC_ATOMICS                     0x38U
#define CSC_DATA_BASE                   0x3CU
#define CSC_WEIGHT_BASE                 0x40U
#define CSC_INPUT_WIDTH_HEIGHT          0x44U
#define CSC_INPUT_CHANNELS              0x48U
#define CSC_KERNEL_WIDTH_HEIGHT         0x4CU
#define CSC_STRIDE_XY                   0x50U
#define CSC_OUTPUT_WIDTH_HEIGHT         0x54U
#define CSC_OUTPUT_CHANNELS             0x58U
#define CACC_STATUS                     0x5CU
#define CACC_CONTROL                    0x60U
#define CACC_DATAOUT_SIZE_0             0x64U
#define CACC_DATAOUT_SIZE_1             0x68U
#define CACC_DATAOUT_ADDR               0x6CU
#define CACC_LINE_STRIDE                0x70U
#define CACC_SURF_STRIDE                0x74U
#define CACC_DATAOUT_MAP                0x78U

#define CDMA_CONTROL_DATA_START         (1U << 0)
#define CDMA_CONTROL_WEIGHT_START       (1U << 1)

#define CDMA_STATUS_DATA_BUSY           (1U << 0)
#define CDMA_STATUS_DATA_DONE           (1U << 1)
#define CDMA_STATUS_DATA_ERROR          (1U << 2)
#define CDMA_STATUS_WEIGHT_BUSY         (1U << 3)
#define CDMA_STATUS_WEIGHT_DONE         (1U << 4)
#define CDMA_STATUS_WEIGHT_ERROR        (1U << 5)

#define CSC_CONTROL_START               (1U << 0)
#define CSC_CONTROL_ENABLE              (1U << 1)

#define CSC_STATUS_READY                (1U << 0)
#define CSC_STATUS_BUSY                 (1U << 1)
#define CSC_STATUS_DONE                 (1U << 2)
#define CSC_STATUS_ERROR                (1U << 3)

#define CACC_CONTROL_START              (1U << 0)
#define CACC_CONTROL_ENABLE             (1U << 1)

#define CACC_STATUS_READY               (1U << 0)
#define CACC_STATUS_BUSY                (1U << 1)
#define CACC_STATUS_DONE                (1U << 2)
#define CACC_STATUS_ERROR               (1U << 3)

#define NPU_MACLANE_NUM                 4U
#define NPU_MACCELL_NUM                 8U
#define NPU_HW_DIM_LIMIT                255U
#define NPU_HW_CHANNEL_LIMIT            255U
#define NPU_CBUF_BANK_DEPTH             1024U
#define NPU_DATA_CBUF_WORD_CAPACITY     \
    (NPU_MACCELL_NUM * NPU_CBUF_BANK_DEPTH)
#define NPU_WEIGHT_CBUF_WORD_CAPACITY   \
    (NPU_MACCELL_NUM * NPU_CBUF_BANK_DEPTH)

#define NPU_POLL_TIMEOUT                100000000U
#define NPU_COMPARE_PRINT_LIMIT         8U

typedef struct {
    u32 csb_base;
    u32 data_src_byte_base;
    u32 weight_src_byte_base;
    u32 output_byte_base;
    u32 output_word_base;
} npu_context_t;

typedef struct {
    u32 input_width;
    u32 input_height;
    u32 input_channels;
    u32 kernel_width;
    u32 kernel_height;
    u32 kernel_count;
    u32 stride_x;
    u32 stride_y;
    u32 output_width;
    u32 output_height;
    u32 output_channels;
    u32 output_positions;
    u32 channel_groups;
    u32 data_words;
    u32 weight_words;
    u32 output_words;
    u32 csc_atomics;
} npu_layer_config_t;

#define NPU_UART_BAUD_RATE              115200U

static inline u32 npu_ceil_div_u32(u32 value, u32 divisor)
{
    if (divisor == 0U) {
        return 0U;
    }

    return (value + divisor - 1U) / divisor;
}

static inline u32 npu_pack_wh(u32 width, u32 height)
{
    return ((height & 0xffffU) << 16) | (width & 0xffffU);
}

static inline int npu_initialize_uart0(void)
{
    XUartPs_Config *config;
    static XUartPs uart;
    int status;

    config = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    if (config == NULL) {
        return XST_FAILURE;
    }

    status = XUartPs_CfgInitialize(&uart, config, config->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    XUartPs_SetOperMode(&uart, XUARTPS_OPER_MODE_NORMAL);
    return XUartPs_SetBaudRate(&uart, NPU_UART_BAUD_RATE);
}

static inline void npu_context_init(
    npu_context_t *npu,
    u32 csb_base,
    u32 data_src_byte_base,
    u32 weight_src_byte_base,
    u32 output_byte_base
)
{
    npu->csb_base = csb_base;
    npu->data_src_byte_base = data_src_byte_base;
    npu->weight_src_byte_base = weight_src_byte_base;
    npu->output_byte_base = output_byte_base;
    npu->output_word_base = output_byte_base >> 2;
}

static inline void npu_layer_config_init(
    npu_layer_config_t *layer,
    u32 input_width,
    u32 input_height,
    u32 input_channels,
    u32 kernel_width,
    u32 kernel_height,
    u32 kernel_count,
    u32 stride_x,
    u32 stride_y
)
{
    layer->input_width = input_width;
    layer->input_height = input_height;
    layer->input_channels = input_channels;
    layer->kernel_width = kernel_width;
    layer->kernel_height = kernel_height;
    layer->kernel_count = kernel_count;
    layer->stride_x = stride_x;
    layer->stride_y = stride_y;
    layer->output_channels = kernel_count;
    layer->channel_groups = npu_ceil_div_u32(input_channels, NPU_MACLANE_NUM);

    if ((stride_x == 0U) || (stride_y == 0U) ||
        (kernel_width == 0U) || (kernel_height == 0U) ||
        (input_width < kernel_width) || (input_height < kernel_height)) {
        layer->output_width = 0U;
        layer->output_height = 0U;
    } else {
        layer->output_width =
            ((input_width - kernel_width) / stride_x) + 1U;
        layer->output_height =
            ((input_height - kernel_height) / stride_y) + 1U;
    }

    layer->output_positions = layer->output_width * layer->output_height;
    layer->data_words =
        input_width * input_height * layer->channel_groups;
    layer->weight_words =
        kernel_width * kernel_height *
        layer->channel_groups * NPU_MACCELL_NUM;
    layer->output_words = layer->output_positions * kernel_count;
    layer->csc_atomics =
        layer->output_positions *
        kernel_width * kernel_height * layer->channel_groups;
}

static inline int npu_layer_config_validate(
    const npu_layer_config_t *layer
)
{
    if ((layer->input_width == 0U) || (layer->input_height == 0U) ||
        (layer->input_channels == 0U) ||
        (layer->kernel_width == 0U) || (layer->kernel_height == 0U) ||
        (layer->kernel_count == 0U) ||
        (layer->stride_x == 0U) || (layer->stride_y == 0U)) {
        xil_printf("Layer config error: zero dimension/control value\r\n");
        return XST_FAILURE;
    }

    if ((layer->input_width > NPU_HW_DIM_LIMIT) ||
        (layer->input_height > NPU_HW_DIM_LIMIT) ||
        (layer->input_channels > NPU_HW_CHANNEL_LIMIT) ||
        (layer->kernel_width > NPU_HW_DIM_LIMIT) ||
        (layer->kernel_height > NPU_HW_DIM_LIMIT) ||
        (layer->kernel_count > NPU_MACCELL_NUM) ||
        (layer->output_width > NPU_HW_DIM_LIMIT) ||
        (layer->output_height > NPU_HW_DIM_LIMIT) ||
        (layer->output_channels > NPU_HW_CHANNEL_LIMIT)) {
        xil_printf("Layer config error: exceeds current HW limits\r\n");
        return XST_FAILURE;
    }

    if ((layer->output_width == 0U) || (layer->output_height == 0U)) {
        xil_printf("Layer config error: invalid convolution window\r\n");
        return XST_FAILURE;
    }

    if (layer->data_words > NPU_DATA_CBUF_WORD_CAPACITY) {
        xil_printf("Layer config error: data CBUF capacity exceeded\r\n");
        return XST_FAILURE;
    }

    if (layer->weight_words > NPU_WEIGHT_CBUF_WORD_CAPACITY) {
        xil_printf("Layer config error: weight CBUF capacity exceeded\r\n");
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

static inline void npu_csb_write(
    const npu_context_t *npu,
    u32 offset,
    u32 value
)
{
    Xil_Out32(npu->csb_base + offset, value);
}

static inline u32 npu_csb_read(const npu_context_t *npu, u32 offset)
{
    return Xil_In32(npu->csb_base + offset);
}

static inline void npu_clear_control_regs(const npu_context_t *npu)
{
    npu_csb_write(npu, CDMA_CONTROL, 0U);
    npu_csb_write(npu, CSC_CONTROL, 0U);
    npu_csb_write(npu, CACC_CONTROL, 0U);
}

static inline void npu_write_ddr_words(
    u32 byte_base,
    const u32 *words,
    u32 word_count
)
{
    volatile u32 *ddr = (volatile u32 *)(UINTPTR)byte_base;
    u32 idx;

    for (idx = 0U; idx < word_count; idx++) {
        ddr[idx] = words[idx];
    }
}

static inline void npu_zero_ddr_words(u32 byte_base, u32 word_count)
{
    volatile u32 *ddr = (volatile u32 *)(UINTPTR)byte_base;
    u32 idx;

    for (idx = 0U; idx < word_count; idx++) {
        ddr[idx] = 0U;
    }
}

static inline void npu_flush_ddr_words(u32 byte_base, u32 word_count)
{
#if NPU_HAS_XIL_CACHE
    Xil_DCacheFlushRange((UINTPTR)byte_base, word_count * sizeof(u32));
#else
    (void)byte_base;
    (void)word_count;
#endif
}

static inline void npu_invalidate_ddr_words(u32 byte_base, u32 word_count)
{
#if NPU_HAS_XIL_CACHE
    Xil_DCacheInvalidateRange((UINTPTR)byte_base, word_count * sizeof(u32));
#else
    (void)byte_base;
    (void)word_count;
#endif
}

static inline void npu_prepare_ddr_vectors(
    const npu_context_t *npu,
    const u32 *input_words,
    u32 input_word_count,
    const u32 *weight_words,
    u32 weight_word_count,
    u32 output_word_count
)
{
    npu_write_ddr_words(npu->data_src_byte_base,
                        input_words,
                        input_word_count);
    npu_write_ddr_words(npu->weight_src_byte_base,
                        weight_words,
                        weight_word_count);
    npu_zero_ddr_words(npu->output_byte_base, output_word_count);

    npu_flush_ddr_words(npu->data_src_byte_base, input_word_count);
    npu_flush_ddr_words(npu->weight_src_byte_base, weight_word_count);
    npu_flush_ddr_words(npu->output_byte_base, output_word_count);
}

static inline int npu_wait_status_mask(
    const npu_context_t *npu,
    u32 status_offset,
    u32 busy_mask,
    u32 done_mask,
    u32 error_mask,
    const char *name
)
{
    u32 status = 0U;
    u32 busy_seen = 0U;

    for (u32 timeout = 0U; timeout < NPU_POLL_TIMEOUT; timeout++) {
        status = npu_csb_read(npu, status_offset);

        if ((status & busy_mask) != 0U) {
            busy_seen = 1U;
        }

        if ((status & error_mask) != 0U) {
            xil_printf("%s FAIL: error observed, status=0x%08lx\r\n",
                       name, (unsigned long)status);
            return XST_FAILURE;
        }

        if ((status & done_mask) != 0U) {
            if (busy_seen == 0U && busy_mask != 0U) {
                xil_printf("%s NOTE: done observed without polling busy\r\n",
                           name);
            }
            xil_printf("%s PASS: status=0x%08lx\r\n",
                       name, (unsigned long)status);
            return XST_SUCCESS;
        }
    }

    xil_printf("%s FAIL: timeout, busy_seen=%lu status=0x%08lx\r\n",
               name, (unsigned long)busy_seen, (unsigned long)status);
    return XST_FAILURE;
}

static inline int npu_wait_ready(
    const npu_context_t *npu,
    u32 status_offset,
    u32 ready_mask,
    u32 error_mask,
    const char *name
)
{
    u32 status = 0U;

    for (u32 timeout = 0U; timeout < NPU_POLL_TIMEOUT; timeout++) {
        status = npu_csb_read(npu, status_offset);

        if ((status & error_mask) != 0U) {
            xil_printf("%s ready FAIL: error observed, status=0x%08lx\r\n",
                       name, (unsigned long)status);
            return XST_FAILURE;
        }

        if ((status & ready_mask) != 0U) {
            xil_printf("%s ready, status=0x%08lx\r\n",
                       name, (unsigned long)status);
            return XST_SUCCESS;
        }
    }

    xil_printf("%s ready FAIL: timeout, status=0x%08lx\r\n",
               name, (unsigned long)status);
    return XST_FAILURE;
}

static inline void npu_program_single_layer_registers(
    const npu_context_t *npu,
    const npu_layer_config_t *layer
)
{
    npu_clear_control_regs(npu);

    npu_csb_write(npu, DATA_MATRIX_WIDTH, layer->input_width);
    npu_csb_write(npu, DATA_MATRIX_HEIGHT, layer->input_height);
    npu_csb_write(npu, DATA_CHANNEL_COUNT, layer->input_channels);
    npu_csb_write(npu, DATA_DST_BASE, 0U);
    npu_csb_write(npu, DATA_SRC_BASE_ADDR, npu->data_src_byte_base);

    npu_csb_write(npu, WEIGHT_MATRIX_WIDTH, layer->weight_words);
    npu_csb_write(npu, WEIGHT_MATRIX_HEIGHT, 1U);
    npu_csb_write(npu, WEIGHT_CHANNEL_COUNT, NPU_MACLANE_NUM);
    npu_csb_write(npu, WEIGHT_DST_BASE, 0U);
    npu_csb_write(npu, WEIGHT_SRC_BASE_ADDR, npu->weight_src_byte_base);

    npu_csb_write(npu, CSC_ATOMICS, layer->csc_atomics);
    npu_csb_write(npu, CSC_DATA_BASE, 0U);
    npu_csb_write(npu, CSC_WEIGHT_BASE, 0U);
    npu_csb_write(npu, CSC_INPUT_WIDTH_HEIGHT,
                  npu_pack_wh(layer->input_width, layer->input_height));
    npu_csb_write(npu, CSC_INPUT_CHANNELS, layer->input_channels);
    npu_csb_write(npu, CSC_KERNEL_WIDTH_HEIGHT,
                  npu_pack_wh(layer->kernel_width, layer->kernel_height));
    npu_csb_write(npu, CSC_STRIDE_XY,
                  npu_pack_wh(layer->stride_x, layer->stride_y));
    npu_csb_write(npu, CSC_OUTPUT_WIDTH_HEIGHT,
                  npu_pack_wh(layer->output_width, layer->output_height));
    npu_csb_write(npu, CSC_OUTPUT_CHANNELS, layer->output_channels);

    npu_csb_write(npu, CACC_DATAOUT_SIZE_0,
                  npu_pack_wh(layer->output_width, layer->output_height));
    npu_csb_write(npu, CACC_DATAOUT_SIZE_1, layer->output_channels);
    npu_csb_write(npu, CACC_DATAOUT_ADDR, npu->output_word_base);
    npu_csb_write(npu, CACC_LINE_STRIDE, layer->output_width);
    npu_csb_write(npu, CACC_SURF_STRIDE, layer->output_positions);
    npu_csb_write(npu, CACC_DATAOUT_MAP, 0U);
}

static inline int npu_run_cdma_loads(const npu_context_t *npu)
{
    xil_printf("Loading DATA pattern...\r\n");
    npu_csb_write(npu, CDMA_CONTROL, CDMA_CONTROL_DATA_START);
    npu_csb_write(npu, CDMA_CONTROL, 0U);
    if (npu_wait_status_mask(npu,
                             CDMA_STATUS,
                             CDMA_STATUS_DATA_BUSY,
                             CDMA_STATUS_DATA_DONE,
                             CDMA_STATUS_DATA_ERROR,
                             "DATA channel") != XST_SUCCESS) {
        return XST_FAILURE;
    }

    xil_printf("Loading WEIGHT pattern...\r\n");
    npu_csb_write(npu, CDMA_CONTROL, CDMA_CONTROL_WEIGHT_START);
    npu_csb_write(npu, CDMA_CONTROL, 0U);
    if (npu_wait_status_mask(npu,
                             CDMA_STATUS,
                             CDMA_STATUS_WEIGHT_BUSY,
                             CDMA_STATUS_WEIGHT_DONE,
                             CDMA_STATUS_WEIGHT_ERROR,
                             "WEIGHT channel") != XST_SUCCESS) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

static inline int npu_run_compute_pipeline(
    const npu_context_t *npu,
    const npu_layer_config_t *layer
)
{
    xil_printf("Running pipeline, atomics=%lu...\r\n",
               (unsigned long)layer->csc_atomics);

    npu_csb_write(npu, CACC_CONTROL, CACC_CONTROL_ENABLE);
    if (npu_wait_ready(npu,
                       CACC_STATUS,
                       CACC_STATUS_READY,
                       CACC_STATUS_ERROR,
                       "CACC/SDP") != XST_SUCCESS) {
        return XST_FAILURE;
    }

    npu_csb_write(npu, CSC_CONTROL, CSC_CONTROL_ENABLE);
    if (npu_wait_ready(npu,
                       CSC_STATUS,
                       CSC_STATUS_READY,
                       CSC_STATUS_ERROR,
                       "CSC") != XST_SUCCESS) {
        return XST_FAILURE;
    }

    npu_csb_write(npu,
                  CACC_CONTROL,
                  CACC_CONTROL_ENABLE | CACC_CONTROL_START);
    npu_csb_write(npu,
                  CSC_CONTROL,
                  CSC_CONTROL_ENABLE | CSC_CONTROL_START);

    if (npu_wait_status_mask(npu,
                             CSC_STATUS,
                             CSC_STATUS_BUSY,
                             CSC_STATUS_DONE,
                             CSC_STATUS_ERROR,
                             "CSC") != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (npu_wait_status_mask(npu,
                             CACC_STATUS,
                             CACC_STATUS_BUSY,
                             CACC_STATUS_DONE,
                             CACC_STATUS_ERROR,
                             "CACC/SDP") != XST_SUCCESS) {
        return XST_FAILURE;
    }

    npu_csb_write(npu, CSC_CONTROL, 0U);
    npu_csb_write(npu, CACC_CONTROL, 0U);

    return XST_SUCCESS;
}

static inline int npu_compare_output_words(
    const npu_context_t *npu,
    const u32 *expected_words,
    u32 word_count
)
{
    volatile u32 *output = (volatile u32 *)(UINTPTR)npu->output_byte_base;
    u32 mismatch_count = 0U;

    npu_invalidate_ddr_words(npu->output_byte_base, word_count);

    for (u32 idx = 0U; idx < word_count; idx++) {
        u32 actual = output[idx];
        u32 expected = expected_words[idx];

        if (idx < NPU_COMPARE_PRINT_LIMIT) {
            xil_printf("DDR[%lu] actual=0x%08lx expected=0x%08lx\r\n",
                       (unsigned long)idx,
                       (unsigned long)actual,
                       (unsigned long)expected);
        }

        if (actual != expected) {
            if (mismatch_count < NPU_COMPARE_PRINT_LIMIT) {
                xil_printf("Mismatch[%lu] idx=%lu actual=0x%08lx expected=0x%08lx\r\n",
                           (unsigned long)mismatch_count,
                           (unsigned long)idx,
                           (unsigned long)actual,
                           (unsigned long)expected);
            }
            mismatch_count++;
        }
    }

    if (mismatch_count != 0U) {
        xil_printf("DDR compare FAIL: mismatches=%lu / %lu\r\n",
                   (unsigned long)mismatch_count,
                   (unsigned long)word_count);
        return XST_FAILURE;
    }

    xil_printf("DDR compare PASS: checked %lu output word(s)\r\n",
               (unsigned long)word_count);
    return XST_SUCCESS;
}

static inline void npu_print_context(const npu_context_t *npu)
{
    xil_printf("NPU context\r\n");
    xil_printf("  CSB target       : %s\r\n", CSB_TARGET_NAME);
    xil_printf("  CSB base         : 0x%08lx\r\n",
               (unsigned long)npu->csb_base);
    xil_printf("  DATA DDR byte    : 0x%08lx\r\n",
               (unsigned long)npu->data_src_byte_base);
    xil_printf("  WEIGHT DDR byte  : 0x%08lx\r\n",
               (unsigned long)npu->weight_src_byte_base);
    xil_printf("  OUTPUT DDR byte  : 0x%08lx\r\n",
               (unsigned long)npu->output_byte_base);
    xil_printf("  OUTPUT DDR word  : 0x%08lx\r\n",
               (unsigned long)npu->output_word_base);
}

static inline void npu_print_status(const npu_context_t *npu)
{
    u32 cdma_status = npu_csb_read(npu, CDMA_STATUS);
    u32 csc_status = npu_csb_read(npu, CSC_STATUS);
    u32 cacc_status = npu_csb_read(npu, CACC_STATUS);

    xil_printf("NPU status\r\n");
    xil_printf("  CDMA status      : 0x%08lx\r\n",
               (unsigned long)cdma_status);
    xil_printf("  CSC status       : 0x%08lx\r\n",
               (unsigned long)csc_status);
    xil_printf("  CACC/SDP status  : 0x%08lx\r\n",
               (unsigned long)cacc_status);
}

static inline void npu_print_layer_config(
    const npu_layer_config_t *layer
)
{
    xil_printf("NPU layer config\r\n");
    xil_printf("  Input WHC        : %lu x %lu x %lu\r\n",
               (unsigned long)layer->input_width,
               (unsigned long)layer->input_height,
               (unsigned long)layer->input_channels);
    xil_printf("  Kernel WH count  : %lu x %lu x %lu\r\n",
               (unsigned long)layer->kernel_width,
               (unsigned long)layer->kernel_height,
               (unsigned long)layer->kernel_count);
    xil_printf("  Stride XY        : %lu x %lu\r\n",
               (unsigned long)layer->stride_x,
               (unsigned long)layer->stride_y);
    xil_printf("  Output WHC       : %lu x %lu x %lu\r\n",
               (unsigned long)layer->output_width,
               (unsigned long)layer->output_height,
               (unsigned long)layer->output_channels);
    xil_printf("  Channel groups   : %lu\r\n",
               (unsigned long)layer->channel_groups);
    xil_printf("  Data words       : %lu\r\n",
               (unsigned long)layer->data_words);
    xil_printf("  Weight words     : %lu\r\n",
               (unsigned long)layer->weight_words);
    xil_printf("  Output words     : %lu\r\n",
               (unsigned long)layer->output_words);
    xil_printf("  CSC atomics      : %lu\r\n",
               (unsigned long)layer->csc_atomics);
}

#endif
