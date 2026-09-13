#include <zephyr/kernel.h>
#include <zephyr/sys/util.h>

#include <hal/nrf_gpio.h>

#if IS_ENABLED(CONFIG_USB_DEVICE_STACK)
#include <zephyr/usb/usb_device.h>
#endif

#define X7_LED1 NRF_GPIO_PIN_MAP(0, 28)
#define X7_LED2 NRF_GPIO_PIN_MAP(0, 29)
#define XIAO_RED_LED NRF_GPIO_PIN_MAP(0, 26)
#define XIAO_GREEN_LED NRF_GPIO_PIN_MAP(0, 30)

int main(void)
{
    nrf_gpio_cfg_output(X7_LED1);
    nrf_gpio_cfg_output(X7_LED2);
    nrf_gpio_cfg_output(XIAO_RED_LED);
    nrf_gpio_cfg_output(XIAO_GREEN_LED);

    nrf_gpio_pin_clear(X7_LED1);
    nrf_gpio_pin_clear(X7_LED2);
    nrf_gpio_pin_set(XIAO_RED_LED);
    nrf_gpio_pin_set(XIAO_GREEN_LED);

#if IS_ENABLED(CONFIG_USB_DEVICE_STACK)
    if (usb_enable(NULL) == 0) {
        nrf_gpio_pin_set(X7_LED2);
        nrf_gpio_pin_clear(XIAO_GREEN_LED);
    }
#else
    nrf_gpio_pin_set(X7_LED2);
    nrf_gpio_pin_clear(XIAO_GREEN_LED);
#endif

    while (1) {
        nrf_gpio_pin_toggle(X7_LED1);
        nrf_gpio_pin_toggle(XIAO_RED_LED);
        k_msleep(500);
    }

    return 0;
}
