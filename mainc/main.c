#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"
#include "xuartps.h"

/*
 * CSB register smoke test.
 *
 * Current XSA exposes the CSB register target at 0x4000_0000. This test does not use the
 * removed debug_axi block. It only checks that software can program the CSB
 * register map and observe busy/done status from CDMA and CSC.
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

#if defined(XPAR_APB_DEBUG_MODULE_0_BASEADDR)
#define DEBUG_BASE                      XPAR_APB_DEBUG_MODULE_0_BASEADDR
#define DEBUG_TARGET_NAME               "APB_DEBUG"
#else
#define DEBUG_BASE                      0x43C10000U
#define DEBUG_TARGET_NAME               "APB_DEBUG_FIXED"
#endif

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

#define DEBUG_CONTROL                   0x00U
#define DEBUG_STATUS                    0x04U
#define DEBUG_READ_INDEX                0x08U
#define DEBUG_CAPTURE_COUNT             0x0CU
#define DEBUG_DATA_BASE                 0x10U
#define DEBUG_WORD_COUNT                8U
#define DEBUG_BUFFER_DEPTH              16U
#define DEBUG_PRINT_SLOTS               4U

#define DEBUG_CONTROL_CLEAR             (1U << 0)
#define DEBUG_CONTROL_CAPTURE_ENABLE    (1U << 1)
#define DEBUG_CONTROL_FREEZE            (1U << 2)
#define DEBUG_CONTROL_OVERWRITE_ENABLE  (1U << 3)
#define DEBUG_CONTROL_IRQ_ENABLE        (1U << 4)

#define DEBUG_STATUS_NON_EMPTY          (1U << 0)
#define DEBUG_STATUS_FULL               (1U << 1)
#define DEBUG_STATUS_OVERFLOW           (1U << 2)
#define DEBUG_STATUS_IRQ                (1U << 5)

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
#define TEST_OUTPUT_WIDTH               14U
#define TEST_OUTPUT_HEIGHT              14U
#define TEST_OUTPUT_CHANNELS            8U
#define TEST_CSC_ATOMICS                \
    (TEST_OUTPUT_WIDTH * TEST_OUTPUT_HEIGHT * \
     TEST_KERNEL_WIDTH * TEST_KERNEL_HEIGHT)

#define TEST_SOURCE_WORD_COUNT          TEST_WEIGHT_WORDS
#define TEST_SOURCE_BYTE_COUNT          (TEST_SOURCE_WORD_COUNT * sizeof(u32))

#define POLL_TIMEOUT                    10000000U
#define STARTUP_DELAY_US                20000000U
#define REPEAT_DELAY_US                 1000000U

static u32 saved_source_words[TEST_SOURCE_WORD_COUNT];
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

static void debug_write(u32 offset, u32 value)
{
    Xil_Out32(DEBUG_BASE + offset, value);
}

static u32 debug_read(u32 offset)
{
    return Xil_In32(DEBUG_BASE + offset);
}

static u32 pack_wh(u32 width, u32 height)
{
    return ((height & 0xffffU) << 16) | (width & 0xffffU);
}

static u32 data_pattern_word(u32 index)
{
    u32 elem_base = 0x10U + (index * 4U);
    u32 lane0 = (elem_base + 0U) & 0xffU;
    u32 lane1 = (elem_base + 1U) & 0xffU;
    u32 lane2 = (elem_base + 2U) & 0xffU;
    u32 lane3 = (elem_base + 3U) & 0xffU;

    return (lane3 << 24) | (lane2 << 16) | (lane1 << 8) | lane0;
}

static u32 weight_pattern_word(u32 index)
{
    u32 elem_base = index * 4U;
    u32 lane0 = (0x80U + elem_base + 0U) & 0xffU;
    u32 lane1 = (0x80U + elem_base + 1U) & 0xffU;
    u32 lane2 = (0x80U + elem_base + 2U) & 0xffU;
    u32 lane3 = (0x80U + elem_base + 3U) & 0xffU;

    return (lane3 << 24) | (lane2 << 16) | (lane1 << 8) | lane0;
}

static int sign_extend8(u32 value)
{
    int byte_value = (int)(value & 0xffU);

    if ((byte_value & 0x80) != 0) {
        byte_value -= 256;
    }

    return byte_value;
}

static u32 expected_debug_psum(u32 output_pos, u32 cell_idx)
{
    u32 out_x = output_pos % TEST_OUTPUT_WIDTH;
    u32 out_y = output_pos / TEST_OUTPUT_WIDTH;
    int sum = 0;
    u32 kernel_x;
    u32 kernel_y;
    u32 channel;

    for (kernel_y = 0U; kernel_y < TEST_KERNEL_HEIGHT; kernel_y++) {
        for (kernel_x = 0U; kernel_x < TEST_KERNEL_WIDTH; kernel_x++) {
            u32 input_x = out_x + kernel_x;
            u32 input_y = out_y + kernel_y;
            u32 input_word_idx =
                (input_y * TEST_DATA_WIDTH) + input_x;
            u32 kernel_idx =
                (kernel_y * TEST_KERNEL_WIDTH) + kernel_x;

            for (channel = 0U; channel < TEST_DATA_CHANNELS; channel++) {
                u32 data_byte =
                    (0x10U + (input_word_idx * TEST_DATA_CHANNELS) +
                     channel) & 0xffU;
                u32 weight_elem_idx =
                    (kernel_idx * DEBUG_WORD_COUNT * TEST_DATA_CHANNELS) +
                    (cell_idx * TEST_DATA_CHANNELS) +
                    channel;
                u32 weight_byte = (0x80U + weight_elem_idx) & 0xffU;

                sum += sign_extend8(data_byte) * sign_extend8(weight_byte);
            }
        }
    }

    return (u32)sum;
}

static void save_source_window(void)
{
    volatile u32 *source = (volatile u32 *)CDMA_AXI_SOURCE_BASE;
    u32 i;

    Xil_DCacheInvalidateRange(
        (UINTPTR)source,
        (u32)TEST_SOURCE_BYTE_COUNT
    );

    for (i = 0U; i < TEST_SOURCE_WORD_COUNT; i++) {
        saved_source_words[i] = source[i];
    }
}

static void restore_source_window(void)
{
    volatile u32 *source = (volatile u32 *)CDMA_AXI_SOURCE_BASE;
    u32 i;

    for (i = 0U; i < TEST_SOURCE_WORD_COUNT; i++) {
        source[i] = saved_source_words[i];
    }

    Xil_DCacheFlushRange(
        (UINTPTR)source,
        (u32)TEST_SOURCE_BYTE_COUNT
    );
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

    Xil_DCacheFlushRange(
        (UINTPTR)source,
        (u32)TEST_SOURCE_BYTE_COUNT
    );
}

static int verify_register_writeback(void)
{
    csb_write(CDMA_CONTROL, 0U);
    csb_write(CSC_CONTROL, 0U);

    csb_write(DATA_MATRIX_WIDTH, TEST_DATA_WIDTH);
    csb_write(DATA_MATRIX_HEIGHT, TEST_DATA_HEIGHT);
    csb_write(DATA_CHANNEL_COUNT, TEST_DATA_CHANNELS);
    csb_write(DATA_DST_BASE, 0U);
    csb_write(WEIGHT_MATRIX_WIDTH, TEST_WEIGHT_WIDTH);
    csb_write(WEIGHT_MATRIX_HEIGHT, TEST_WEIGHT_HEIGHT);
    csb_write(WEIGHT_CHANNEL_COUNT, TEST_WEIGHT_CHANNELS);
    csb_write(WEIGHT_DST_BASE, 0U);
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

    xil_printf("Register writeback check PASSED\r\n");
    return XST_SUCCESS;
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

static void configure_csc_smoke(void)
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

static void arm_debug_capture(void)
{
    debug_write(
        DEBUG_CONTROL,
        DEBUG_CONTROL_CLEAR | DEBUG_CONTROL_CAPTURE_ENABLE
    );
}

static int dump_debug_capture(void)
{
    u32 status;
    u32 capture_count;
    u32 stored_count;
    u32 write_index;
    u32 read_index;
    u32 dump_count;
    u32 value;
    u32 expected;
    u32 fail_mask;
    u32 slot;
    u32 i;

    status = debug_read(DEBUG_STATUS);
    capture_count = debug_read(DEBUG_CAPTURE_COUNT);
    stored_count = (status >> 8) & 0xffU;
    write_index = (status >> 16) & 0xffU;
    read_index = (status >> 24) & 0xffU;

    xil_printf(
        "DBG status=0x%08x stored=%d wr=%d rd=%d capture_count=%d\r\n",
        status,
        stored_count,
        write_index,
        read_index,
        capture_count
    );

    if ((status & DEBUG_STATUS_NON_EMPTY) == 0U) {
        xil_printf("DBG FAIL: no CMAC psum snapshots captured\r\n");
        return XST_FAILURE;
    }

    if ((status & DEBUG_STATUS_OVERFLOW) != 0U) {
        xil_printf("DBG warning: snapshot overflow observed\r\n");
    }

    dump_count = stored_count;
    if (dump_count > DEBUG_BUFFER_DEPTH) {
        dump_count = DEBUG_BUFFER_DEPTH;
    }

    for (slot = 0U; slot < dump_count; slot++) {
        debug_write(DEBUG_READ_INDEX, slot);
        fail_mask = 0U;

        if (slot < DEBUG_PRINT_SLOTS) {
            xil_printf("DBG slot[%d] output_pos=%d\r\n", slot, slot);
        }

        for (i = 0U; i < DEBUG_WORD_COUNT; i++) {
            value = debug_read(DEBUG_DATA_BASE + (i * sizeof(u32)));
            expected = expected_debug_psum(slot, i);

            if (value != expected) {
                fail_mask |= (1U << i);
            }

            if ((slot < DEBUG_PRINT_SLOTS) || (value != expected)) {
                xil_printf(
                    "  psum[%d] actual=0x%08x (%d) expected=0x%08x (%d)\r\n",
                    i,
                    value,
                    (int)value,
                    expected,
                    (int)expected
                );
            }
        }

        if (fail_mask != 0U) {
            xil_printf(
                "DBG FAIL: slot[%d] mismatch mask=0x%02x\r\n",
                slot,
                fail_mask
            );
            return XST_FAILURE;
        }
    }

    xil_printf("DBG compare PASS: checked %d snapshot(s)\r\n", dump_count);

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

static int wait_csc_ready(int *busy_seen)
{
    u32 timeout;
    u32 status = 0U;

    for (timeout = 0U; timeout < POLL_TIMEOUT; timeout++) {
        status = csb_read(CSC_STATUS);

        if ((status & CSC_STATUS_ERROR) != 0U) {
            xil_printf("CSC error before start, status=0x%08x\r\n", status);
            return XST_FAILURE;
        }

        if ((status & CSC_STATUS_BUSY) != 0U) {
            *busy_seen = 1;
        }

        if ((status & CSC_STATUS_READY) != 0U) {
            xil_printf("CSC ready, status=0x%08x\r\n", status);
            return XST_SUCCESS;
        }
    }

    xil_printf("CSC ready timeout, status=0x%08x\r\n", status);
    return XST_FAILURE;
}

static int wait_csc_complete(int busy_seen)
{
    u32 timeout;
    u32 status = 0U;
    int done_seen = 0;

    for (timeout = 0U; timeout < POLL_TIMEOUT; timeout++) {
        status = csb_read(CSC_STATUS);

        if ((status & CSC_STATUS_ERROR) != 0U) {
            xil_printf("CSC error, status=0x%08x\r\n", status);
            return XST_FAILURE;
        }

        if ((status & CSC_STATUS_BUSY) != 0U) {
            busy_seen = 1;
        }

        if ((status & CSC_STATUS_DONE) != 0U) {
            done_seen = 1;
        }

        if ((busy_seen != 0) && (done_seen != 0) &&
            ((status & CSC_STATUS_BUSY) == 0U)) {
            xil_printf(
                "CSC PASS: busy observed, done observed, status=0x%08x\r\n",
                status
            );
            return XST_SUCCESS;
        }
    }

    xil_printf(
        "CSC FAIL: timeout, busy_seen=%d done_seen=%d status=0x%08x\r\n",
        busy_seen,
        done_seen,
        status
    );
    return XST_FAILURE;
}

static int run_csc_smoke(void)
{
    int busy_seen = 0;
    int status;

    configure_csc_smoke();
    arm_debug_capture();

    csb_write(CSC_CONTROL, CSC_CONTROL_ENABLE);
    if (wait_csc_ready(&busy_seen) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    csb_write(CSC_CONTROL, CSC_CONTROL_ENABLE | CSC_CONTROL_START);
    status = wait_csc_complete(busy_seen);
    if (status != XST_SUCCESS) {
        return status;
    }

    return dump_debug_capture();
}

int main(void)
{
    if (initialize_uart0() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    xil_printf("\r\n%s CDMA+CSC register smoke test\r\n", CSB_TARGET_NAME);
    xil_printf("UART0: MIO14 RX / MIO15 TX / 115200 8N1\r\n");
    xil_printf("%s CSB base : 0x%08x\r\n", CSB_TARGET_NAME, CSB_BASE);
    xil_printf("%s base : 0x%08x\r\n", DEBUG_TARGET_NAME, DEBUG_BASE);
    xil_printf("Fixed AXI source : 0x%08x\r\n", CDMA_AXI_SOURCE_BASE);
    xil_printf("Waiting 20 seconds before CSB/DDR writes...\r\n");
    usleep(STARTUP_DELAY_US);

    configure_cdma_loads();
    configure_csc_smoke();

    if (verify_register_writeback() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    save_source_window();

    while (1) {
        test_iteration++;
        last_test_result = XST_FAILURE;

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

        xil_printf("Iteration %d: loading WEIGHT pattern...\r\n",
                   test_iteration);
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

        xil_printf("Iteration %d: running CSC smoke, atomics=%d...\r\n",
                   test_iteration,
                   TEST_CSC_ATOMICS);
        if (run_csc_smoke() != XST_SUCCESS) {
            goto iteration_done;
        }

        last_test_result = XST_SUCCESS;

iteration_done:
        restore_source_window();
        csb_write(CDMA_CONTROL, 0U);
        csb_write(CSC_CONTROL, 0U);

        xil_printf(
            "Iteration %d: %s CDMA+CSC register smoke test %s\r\n",
            test_iteration,
            CSB_TARGET_NAME,
            (last_test_result == XST_SUCCESS) ? "PASSED" : "FAILED"
        );

        usleep(REPEAT_DELAY_US);
    }
}
