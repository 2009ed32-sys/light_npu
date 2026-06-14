#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"
#include "xuartps.h"

/*
 * APB_TOP CDMA + CSC + CMAC + CACC + SDP DDR writeback debug test.
 *
 * The test uses one 16x16x4 input cube and three 3x3x4 kernels. CDMA loads
 * the input and weight patterns into CBUF, CSC/CMAC/CACC produce psums, SDP
 * writes the selected psums back to DDR, and the CPU verifies the DDR contents.
 */

#define UART_BAUD_RATE                  115200U

#if defined(XPAR_APB_TOP_0_BASEADDR)
#define CSB_BASE                        XPAR_APB_TOP_0_BASEADDR
#define CSB_TARGET_NAME                 "APB_TOP"
#else
#define CSB_BASE                        0x43C00000U
#define CSB_TARGET_NAME                 "APB_TOP_FIXED"
#endif

#define CDMA_AXI_SOURCE_BASE            0x00000000U
#define OUTPUT_DDR_BYTE_BASE            0x01000000U
#define OUTPUT_DDR_WORD_BASE            (OUTPUT_DDR_BYTE_BASE >> 2)

#define CDMA_CONTROL                    0x00U
#define CDMA_STATUS                     0x04U
#define DATA_MATRIX_WIDTH               0x08U
#define DATA_MATRIX_HEIGHT              0x0CU
#define DATA_CHANNEL_COUNT              0x10U
#define DATA_DST_BASE                   0x14U
#define WEIGHT_MATRIX_WIDTH             0x18U
#define WEIGHT_MATRIX_HEIGHT            0x1CU
#define WEIGHT_CHANNEL_COUNT            0x20U
#define WEIGHT_DST_BASE                 0x24U
#define CSC_CONTROL                     0x28U
#define CSC_STATUS                      0x2CU
#define CSC_ATOMICS                     0x30U
#define CSC_DATA_BASE                   0x34U
#define CSC_WEIGHT_BASE                 0x38U
#define CSC_INPUT_WIDTH_HEIGHT          0x3CU
#define CSC_INPUT_CHANNELS              0x40U
#define CSC_KERNEL_WIDTH_HEIGHT         0x44U
#define CSC_STRIDE_XY                   0x48U
#define CSC_OUTPUT_WIDTH_HEIGHT         0x4CU
#define CSC_OUTPUT_CHANNELS             0x50U
#define CACC_STATUS                     0x54U
#define CACC_CONTROL                    0x58U
#define CACC_DATAOUT_SIZE_0             0x5CU
#define CACC_DATAOUT_SIZE_1             0x60U
#define CACC_DATAOUT_ADDR               0x64U
#define CACC_LINE_STRIDE                0x68U
#define CACC_SURF_STRIDE                0x6CU
#define CACC_DATAOUT_MAP                0x70U

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

#define TEST_DATA_WIDTH                 16U
#define TEST_DATA_HEIGHT                16U
#define TEST_DATA_CHANNELS              4U
#define TEST_DATA_WORDS                 \
    (TEST_DATA_WIDTH * TEST_DATA_HEIGHT)

#define TEST_WEIGHT_WIDTH               256U
#define TEST_WEIGHT_HEIGHT              1U
#define TEST_WEIGHT_CHANNELS            4U
#define TEST_WEIGHT_WORDS               \
    (TEST_WEIGHT_WIDTH * TEST_WEIGHT_HEIGHT)

#define TEST_KERNEL_WIDTH               3U
#define TEST_KERNEL_HEIGHT              3U
#define TEST_KERNEL_COUNT               3U
#define TEST_OUTPUT_WIDTH               \
    (TEST_DATA_WIDTH - TEST_KERNEL_WIDTH + 1U)
#define TEST_OUTPUT_HEIGHT              \
    (TEST_DATA_HEIGHT - TEST_KERNEL_HEIGHT + 1U)
#define TEST_OUTPUT_CHANNELS            TEST_KERNEL_COUNT
#define TEST_OUTPUT_POSITIONS           \
    (TEST_OUTPUT_WIDTH * TEST_OUTPUT_HEIGHT)
#define TEST_OUTPUT_WORDS               \
    (TEST_OUTPUT_POSITIONS * TEST_OUTPUT_CHANNELS)
#define TEST_CSC_ATOMICS                \
    (TEST_OUTPUT_WIDTH * TEST_OUTPUT_HEIGHT * \
     TEST_KERNEL_WIDTH * TEST_KERNEL_HEIGHT)

#define MACCELL_NUM                     8U
#define MACLANE_NUM                     4U

#define TEST_SOURCE_WORD_COUNT          TEST_WEIGHT_WORDS
#define TEST_SOURCE_BYTE_COUNT          (TEST_SOURCE_WORD_COUNT * sizeof(u32))
#define TEST_OUTPUT_BYTE_COUNT          (TEST_OUTPUT_WORDS * sizeof(u32))

#define POLL_TIMEOUT                    10000000U
#define STARTUP_DELAY_US                20000000U
#define REPEAT_DELAY_US                 1000000U
#define PRINT_OUTPUT_SLOTS              8U
#define STATUS_TRACE_LIMIT              8U

static u32 saved_source_words[TEST_SOURCE_WORD_COUNT];
static u32 saved_output_words[TEST_OUTPUT_WORDS];
volatile u32 test_iteration;
volatile int last_test_result = XST_FAILURE;

static int initialize_uart0(void)
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
    return XUartPs_SetBaudRate(&uart, UART_BAUD_RATE);
}

static void csb_write(u32 offset, u32 value)
{
    Xil_Out32(CSB_BASE + offset, value);
}

static u32 csb_read(u32 offset)
{
    return Xil_In32(CSB_BASE + offset);
}

static u32 pack_wh(u32 width, u32 height)
{
    return ((height & 0xffffU) << 16) | (width & 0xffffU);
}

static int sign_extend8(u32 value)
{
    int byte_value = (int)(value & 0xffU);

    if ((byte_value & 0x80) != 0) {
        byte_value -= 256;
    }

    return byte_value;
}

static u32 data_pattern_word(u32 index)
{
    u32 elem_base = 0x10U + (index * TEST_DATA_CHANNELS);
    u32 lane0 = (elem_base + 0U) & 0xffU;
    u32 lane1 = (elem_base + 1U) & 0xffU;
    u32 lane2 = (elem_base + 2U) & 0xffU;
    u32 lane3 = (elem_base + 3U) & 0xffU;

    return (lane3 << 24) | (lane2 << 16) | (lane1 << 8) | lane0;
}

static int weight_pattern_value(u32 kernel_out, u32 kernel_idx, u32 channel)
{
    int kernel_term = (int)kernel_idx;
    int channel_term = (int)channel;

    switch (kernel_out) {
    case 0U:
        return 1 + kernel_term + channel_term;
    case 1U:
        return -1 - kernel_term - channel_term;
    case 2U:
        if ((kernel_idx & 1U) != 0U) {
            return -3 - channel_term;
        }
        return 3 + channel_term;
    default:
        return 0;
    }
}

static u32 weight_pattern_word(u32 index)
{
    u32 lane;
    u32 result = 0U;

    for (lane = 0U; lane < MACLANE_NUM; lane++) {
        u32 elem_idx = (index * MACLANE_NUM) + lane;
        u32 elem_in_kernel = elem_idx % (MACCELL_NUM * MACLANE_NUM);
        u32 kernel_idx = elem_idx / (MACCELL_NUM * MACLANE_NUM);
        u32 kernel_out = elem_in_kernel / MACLANE_NUM;
        u32 channel = elem_in_kernel % MACLANE_NUM;
        int value = 0;

        if ((kernel_idx < (TEST_KERNEL_WIDTH * TEST_KERNEL_HEIGHT)) &&
            (kernel_out < TEST_KERNEL_COUNT)) {
            value = weight_pattern_value(kernel_out, kernel_idx, channel);
        }

        result |= (((u32)value) & 0xffU) << (lane * 8U);
    }

    return result;
}

static int data_pattern_value(u32 x, u32 y, u32 channel)
{
    u32 word_idx = (y * TEST_DATA_WIDTH) + x;
    u32 byte_value =
        (0x10U + (word_idx * TEST_DATA_CHANNELS) + channel) & 0xffU;

    return sign_extend8(byte_value);
}

static u32 expected_output_word(u32 output_pos, u32 kernel_out)
{
    u32 out_x = output_pos % TEST_OUTPUT_WIDTH;
    u32 out_y = output_pos / TEST_OUTPUT_WIDTH;
    u32 kernel_x;
    u32 kernel_y;
    u32 channel;
    int sum = 0;

    for (kernel_y = 0U; kernel_y < TEST_KERNEL_HEIGHT; kernel_y++) {
        for (kernel_x = 0U; kernel_x < TEST_KERNEL_WIDTH; kernel_x++) {
            u32 input_x = out_x + kernel_x;
            u32 input_y = out_y + kernel_y;
            u32 kernel_idx =
                (kernel_y * TEST_KERNEL_WIDTH) + kernel_x;

            for (channel = 0U; channel < TEST_DATA_CHANNELS; channel++) {
                int data_value =
                    data_pattern_value(input_x, input_y, channel);
                int weight_value =
                    weight_pattern_value(kernel_out, kernel_idx, channel);

                sum += data_value * weight_value;
            }
        }
    }

    return (u32)sum;
}

static void save_memory_windows(void)
{
    volatile u32 *source = (volatile u32 *)CDMA_AXI_SOURCE_BASE;
    volatile u32 *output = (volatile u32 *)OUTPUT_DDR_BYTE_BASE;
    u32 i;

    Xil_DCacheInvalidateRange((UINTPTR)source, (u32)TEST_SOURCE_BYTE_COUNT);
    Xil_DCacheInvalidateRange((UINTPTR)output, (u32)TEST_OUTPUT_BYTE_COUNT);

    for (i = 0U; i < TEST_SOURCE_WORD_COUNT; i++) {
        saved_source_words[i] = source[i];
    }

    for (i = 0U; i < TEST_OUTPUT_WORDS; i++) {
        saved_output_words[i] = output[i];
    }
}

static void restore_memory_windows(void)
{
    volatile u32 *source = (volatile u32 *)CDMA_AXI_SOURCE_BASE;
    volatile u32 *output = (volatile u32 *)OUTPUT_DDR_BYTE_BASE;
    u32 i;

    for (i = 0U; i < TEST_SOURCE_WORD_COUNT; i++) {
        source[i] = saved_source_words[i];
    }

    for (i = 0U; i < TEST_OUTPUT_WORDS; i++) {
        output[i] = saved_output_words[i];
    }

    Xil_DCacheFlushRange((UINTPTR)source, (u32)TEST_SOURCE_BYTE_COUNT);
    Xil_DCacheFlushRange((UINTPTR)output, (u32)TEST_OUTPUT_BYTE_COUNT);
}

static void clear_output_window(void)
{
    volatile u32 *output = (volatile u32 *)OUTPUT_DDR_BYTE_BASE;
    u32 i;

    for (i = 0U; i < TEST_OUTPUT_WORDS; i++) {
        output[i] = 0xdead0000U | (i & 0xffffU);
    }

    Xil_DCacheFlushRange((UINTPTR)output, (u32)TEST_OUTPUT_BYTE_COUNT);
}

static void write_source_pattern(int weight_pattern)
{
    volatile u32 *source = (volatile u32 *)CDMA_AXI_SOURCE_BASE;
    u32 i;

    for (i = 0U; i < TEST_SOURCE_WORD_COUNT; i++) {
        source[i] = (weight_pattern != 0) ?
            weight_pattern_word(i) :
            data_pattern_word(i);
    }

    Xil_DCacheFlushRange((UINTPTR)source, (u32)TEST_SOURCE_BYTE_COUNT);
}

static void configure_cdma_loads(void)
{
    csb_write(CDMA_CONTROL, 0U);

    csb_write(DATA_MATRIX_WIDTH, TEST_DATA_WIDTH);
    csb_write(DATA_MATRIX_HEIGHT, TEST_DATA_HEIGHT);
    csb_write(DATA_CHANNEL_COUNT, TEST_DATA_CHANNELS);
    csb_write(DATA_DST_BASE, 0U);

    csb_write(WEIGHT_MATRIX_WIDTH, TEST_WEIGHT_WIDTH);
    csb_write(WEIGHT_MATRIX_HEIGHT, TEST_WEIGHT_HEIGHT);
    csb_write(WEIGHT_CHANNEL_COUNT, TEST_WEIGHT_CHANNELS);
    csb_write(WEIGHT_DST_BASE, 0U);
}

static void configure_csc(void)
{
    csb_write(CSC_CONTROL, 0U);
    csb_write(CSC_ATOMICS, TEST_CSC_ATOMICS);
    csb_write(CSC_DATA_BASE, 0U);
    csb_write(CSC_WEIGHT_BASE, 0U);
    csb_write(CSC_INPUT_WIDTH_HEIGHT,
              pack_wh(TEST_DATA_WIDTH, TEST_DATA_HEIGHT));
    csb_write(CSC_INPUT_CHANNELS, TEST_DATA_CHANNELS);
    csb_write(CSC_KERNEL_WIDTH_HEIGHT,
              pack_wh(TEST_KERNEL_WIDTH, TEST_KERNEL_HEIGHT));
    csb_write(CSC_STRIDE_XY, pack_wh(1U, 1U));
    csb_write(CSC_OUTPUT_WIDTH_HEIGHT,
              pack_wh(TEST_OUTPUT_WIDTH, TEST_OUTPUT_HEIGHT));
    csb_write(CSC_OUTPUT_CHANNELS, TEST_OUTPUT_CHANNELS);
}

static void configure_cacc_sdp(void)
{
    csb_write(CACC_CONTROL, 0U);
    csb_write(CACC_DATAOUT_SIZE_0,
              pack_wh(TEST_OUTPUT_WIDTH, TEST_OUTPUT_HEIGHT));
    csb_write(CACC_DATAOUT_SIZE_1, TEST_OUTPUT_CHANNELS);
    csb_write(CACC_DATAOUT_ADDR, OUTPUT_DDR_WORD_BASE);
    csb_write(CACC_LINE_STRIDE, TEST_OUTPUT_WIDTH);
    csb_write(CACC_SURF_STRIDE,
              TEST_OUTPUT_WIDTH * TEST_OUTPUT_HEIGHT);
    csb_write(CACC_DATAOUT_MAP, 0U);
}

static int verify_register_writeback(void)
{
    configure_cdma_loads();
    configure_csc();
    configure_cacc_sdp();

    if (csb_read(DATA_MATRIX_WIDTH) != TEST_DATA_WIDTH) {
        xil_printf("Register check failed: DATA_MATRIX_WIDTH\r\n");
        return XST_FAILURE;
    }

    if (csb_read(WEIGHT_MATRIX_WIDTH) != TEST_WEIGHT_WIDTH) {
        xil_printf("Register check failed: WEIGHT_MATRIX_WIDTH\r\n");
        return XST_FAILURE;
    }

    if (csb_read(CSC_ATOMICS) != TEST_CSC_ATOMICS) {
        xil_printf("Register check failed: CSC_ATOMICS\r\n");
        return XST_FAILURE;
    }

    if (csb_read(CSC_OUTPUT_CHANNELS) != TEST_OUTPUT_CHANNELS) {
        xil_printf("Register check failed: CSC_OUTPUT_CHANNELS\r\n");
        return XST_FAILURE;
    }

    if (csb_read(CACC_DATAOUT_ADDR) != OUTPUT_DDR_WORD_BASE) {
        xil_printf("Register check failed: CACC_DATAOUT_ADDR\r\n");
        return XST_FAILURE;
    }

    xil_printf("Register writeback check PASSED\r\n");
    return XST_SUCCESS;
}

static int run_cdma_channel(
    const char *name,
    u32 start_mask,
    u32 busy_mask,
    u32 done_mask,
    u32 error_mask
)
{
    u32 timeout;
    u32 status = 0U;
    int busy_seen = 0;
    int done_seen = 0;

    csb_write(CDMA_CONTROL, 0U);
    csb_write(CDMA_CONTROL, start_mask);
    csb_write(CDMA_CONTROL, 0U);

    for (timeout = 0U; timeout < POLL_TIMEOUT; timeout++) {
        status = csb_read(CDMA_STATUS);

        if ((status & error_mask) != 0U) {
            xil_printf("%s error, status=0x%08x\r\n", name, status);
            return XST_FAILURE;
        }

        if ((status & busy_mask) != 0U) {
            busy_seen = 1;
        }

        if ((status & done_mask) != 0U) {
            done_seen = 1;
        }

        if ((busy_seen != 0) && (done_seen != 0) &&
            ((status & busy_mask) == 0U)) {
            xil_printf(
                "%s PASS: busy observed, done observed, status=0x%08x\r\n",
                name,
                status
            );
            return XST_SUCCESS;
        }
    }

    xil_printf(
        "%s FAIL: timeout, busy_seen=%d done_seen=%d status=0x%08x\r\n",
        name,
        busy_seen,
        done_seen,
        status
    );
    return XST_FAILURE;
}

static void print_status_decode(
    const char *name,
    u32 status,
    u32 ready_mask,
    u32 busy_mask,
    u32 done_mask,
    u32 error_mask
)
{
    xil_printf(
        "%s status decode: raw=0x%08x ready=%d busy=%d done=%d error=%d\r\n",
        name,
        status,
        ((status & ready_mask) != 0U) ? 1 : 0,
        ((status & busy_mask) != 0U) ? 1 : 0,
        ((status & done_mask) != 0U) ? 1 : 0,
        ((status & error_mask) != 0U) ? 1 : 0
    );
}

static int wait_status_ready(
    const char *name,
    u32 status_offset,
    u32 ready_mask,
    u32 busy_mask,
    u32 error_mask,
    int *busy_seen
)
{
    u32 timeout;
    u32 status = 0U;

    for (timeout = 0U; timeout < POLL_TIMEOUT; timeout++) {
        status = csb_read(status_offset);

        if ((status & error_mask) != 0U) {
            xil_printf("%s error before start, status=0x%08x\r\n",
                       name,
                       status);
            return XST_FAILURE;
        }

        if ((status & busy_mask) != 0U) {
            *busy_seen = 1;
        }

        if ((status & ready_mask) != 0U) {
            xil_printf("%s ready, status=0x%08x\r\n", name, status);
            return XST_SUCCESS;
        }
    }

    xil_printf("%s ready timeout, status=0x%08x\r\n", name, status);
    return XST_FAILURE;
}

static int wait_status_complete(
    const char *name,
    u32 status_offset,
    u32 ready_mask,
    u32 busy_mask,
    u32 done_mask,
    u32 error_mask,
    int busy_seen,
    int require_busy_seen
)
{
    u32 timeout;
    u32 status = 0U;
    u32 last_status = 0xffffffffU;
    u32 trace_count = 0U;
    int done_seen = 0;

    for (timeout = 0U; timeout < POLL_TIMEOUT; timeout++) {
        status = csb_read(status_offset);

        if ((status != last_status) && (trace_count < STATUS_TRACE_LIMIT)) {
            print_status_decode(
                name,
                status,
                ready_mask,
                busy_mask,
                done_mask,
                error_mask
            );
            last_status = status;
            trace_count++;
        }

        if ((status & error_mask) != 0U) {
            xil_printf("%s error, status=0x%08x\r\n", name, status);
            print_status_decode(
                name,
                status,
                ready_mask,
                busy_mask,
                done_mask,
                error_mask
            );
            return XST_FAILURE;
        }

        if ((status & busy_mask) != 0U) {
            busy_seen = 1;
        }

        if ((status & done_mask) != 0U) {
            done_seen = 1;
        }

        if (((busy_seen != 0) || (require_busy_seen == 0)) &&
            (done_seen != 0) &&
            ((status & busy_mask) == 0U)) {
            if ((busy_seen == 0) && (require_busy_seen == 0)) {
                xil_printf(
                    "%s NOTE: done observed without busy; accepting polling-missed busy\r\n",
                    name
                );
            }
            xil_printf(
                "%s PASS: busy_seen=%d done_seen=%d status=0x%08x\r\n",
                name,
                busy_seen,
                done_seen,
                status
            );
            return XST_SUCCESS;
        }
    }

    xil_printf(
        "%s FAIL: timeout, busy_seen=%d done_seen=%d require_busy=%d status=0x%08x\r\n",
        name,
        busy_seen,
        done_seen,
        require_busy_seen,
        status
    );
    print_status_decode(
        name,
        status,
        ready_mask,
        busy_mask,
        done_mask,
        error_mask
    );
    return XST_FAILURE;
}

static int run_conv_pipeline(void)
{
    int cacc_busy_seen = 0;
    int csc_busy_seen = 0;

    configure_csc();
    configure_cacc_sdp();
    clear_output_window();

    csb_write(CACC_CONTROL, CACC_CONTROL_ENABLE);
    if (wait_status_ready(
            "CACC/SDP",
            CACC_STATUS,
            CACC_STATUS_READY,
            CACC_STATUS_BUSY,
            CACC_STATUS_ERROR,
            &cacc_busy_seen
        ) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    csb_write(CSC_CONTROL, CSC_CONTROL_ENABLE);
    if (wait_status_ready(
            "CSC",
            CSC_STATUS,
            CSC_STATUS_READY,
            CSC_STATUS_BUSY,
            CSC_STATUS_ERROR,
            &csc_busy_seen
        ) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    csb_write(CACC_CONTROL, CACC_CONTROL_ENABLE | CACC_CONTROL_START);
    csb_write(CSC_CONTROL, CSC_CONTROL_ENABLE | CSC_CONTROL_START);

    if (wait_status_complete(
            "CSC",
            CSC_STATUS,
            CSC_STATUS_READY,
            CSC_STATUS_BUSY,
            CSC_STATUS_DONE,
            CSC_STATUS_ERROR,
            csc_busy_seen,
            1
        ) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (wait_status_complete(
            "CACC/SDP",
            CACC_STATUS,
            CACC_STATUS_READY,
            CACC_STATUS_BUSY,
            CACC_STATUS_DONE,
            CACC_STATUS_ERROR,
            cacc_busy_seen,
            0
        ) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

static int verify_output_dram(void)
{
    volatile u32 *output = (volatile u32 *)OUTPUT_DDR_BYTE_BASE;
    u32 i;
    u32 print_count;

    Xil_DCacheInvalidateRange(
        (UINTPTR)output,
        (u32)TEST_OUTPUT_BYTE_COUNT
    );

    print_count = TEST_OUTPUT_WORDS;
    if (print_count > PRINT_OUTPUT_SLOTS) {
        print_count = PRINT_OUTPUT_SLOTS;
    }

    for (i = 0U; i < TEST_OUTPUT_WORDS; i++) {
        u32 output_pos = i / TEST_OUTPUT_CHANNELS;
        u32 kernel_out = i % TEST_OUTPUT_CHANNELS;
        u32 actual = output[i];
        u32 expected = expected_output_word(output_pos, kernel_out);

        if ((i < print_count) || (actual != expected)) {
            xil_printf(
                "DDR[%d] out_pos=%d kernel=%d actual=0x%08x (%d) expected=0x%08x (%d)\r\n",
                i,
                output_pos,
                kernel_out,
                actual,
                (int)actual,
                expected,
                (int)expected
            );
        }

        if (actual != expected) {
            xil_printf("DDR compare FAIL at word %d\r\n", i);
            return XST_FAILURE;
        }
    }

    xil_printf("DDR compare PASS: checked %d output word(s)\r\n",
               TEST_OUTPUT_WORDS);
    return XST_SUCCESS;
}

int main(void)
{
    if (initialize_uart0() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    xil_printf("\r\n%s CDMA+CSC+CMAC+CACC+SDP DDR debug test\r\n",
               CSB_TARGET_NAME);
    xil_printf("UART0: MIO14 RX / MIO15 TX / 115200 8N1\r\n");
    xil_printf("%s CSB base       : 0x%08x\r\n",
               CSB_TARGET_NAME,
               CSB_BASE);
    xil_printf("Fixed AXI source   : 0x%08x\r\n", CDMA_AXI_SOURCE_BASE);
    xil_printf("Output DDR byte    : 0x%08x\r\n", OUTPUT_DDR_BYTE_BASE);
    xil_printf("Output DDR word    : 0x%08x\r\n", OUTPUT_DDR_WORD_BASE);
    xil_printf("Input              : %dx%dx%d\r\n",
               TEST_DATA_WIDTH,
               TEST_DATA_HEIGHT,
               TEST_DATA_CHANNELS);
    xil_printf("Kernel             : %dx%dx%d, count=%d\r\n",
               TEST_KERNEL_WIDTH,
               TEST_KERNEL_HEIGHT,
               TEST_DATA_CHANNELS,
               TEST_KERNEL_COUNT);
    xil_printf("Output             : %dx%dx%d, words=%d\r\n",
               TEST_OUTPUT_WIDTH,
               TEST_OUTPUT_HEIGHT,
               TEST_OUTPUT_CHANNELS,
               TEST_OUTPUT_WORDS);
    xil_printf("Waiting 20 seconds before CSB/DDR writes...\r\n");
    usleep(STARTUP_DELAY_US);

    if (verify_register_writeback() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    save_memory_windows();

    while (1) {
        test_iteration++;
        last_test_result = XST_FAILURE;

        configure_cdma_loads();

        xil_printf("\r\nIteration %d: loading DATA pattern...\r\n",
                   test_iteration);
        write_source_pattern(0);
        if (run_cdma_channel(
                "DATA",
                CDMA_CONTROL_DATA_START,
                CDMA_STATUS_DATA_BUSY,
                CDMA_STATUS_DATA_DONE,
                CDMA_STATUS_DATA_ERROR
            ) != XST_SUCCESS) {
            goto iteration_done;
        }

        xil_printf("Iteration %d: loading WEIGHT pattern, kernels=%d...\r\n",
                   test_iteration,
                   TEST_KERNEL_COUNT);
        write_source_pattern(1);
        if (run_cdma_channel(
                "WEIGHT",
                CDMA_CONTROL_WEIGHT_START,
                CDMA_STATUS_WEIGHT_BUSY,
                CDMA_STATUS_WEIGHT_DONE,
                CDMA_STATUS_WEIGHT_ERROR
            ) != XST_SUCCESS) {
            goto iteration_done;
        }

        xil_printf(
            "Iteration %d: running pipeline, atomics=%d...\r\n",
            test_iteration,
            TEST_CSC_ATOMICS
        );
        if (run_conv_pipeline() != XST_SUCCESS) {
            goto iteration_done;
        }

        xil_printf("Iteration %d: checking output DDR...\r\n",
                   test_iteration);
        if (verify_output_dram() != XST_SUCCESS) {
            goto iteration_done;
        }

        last_test_result = XST_SUCCESS;

iteration_done:
        restore_memory_windows();
        csb_write(CDMA_CONTROL, 0U);
        csb_write(CSC_CONTROL, 0U);
        csb_write(CACC_CONTROL, 0U);

        xil_printf(
            "Iteration %d: %s DDR writeback debug test %s\r\n",
            test_iteration,
            CSB_TARGET_NAME,
            (last_test_result == XST_SUCCESS) ? "PASSED" : "FAILED"
        );

        usleep(REPEAT_DELAY_US);
    }
}
