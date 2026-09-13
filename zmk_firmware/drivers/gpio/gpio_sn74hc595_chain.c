/*
 * Daisy-chained 74HC595 shift register GPIO driver.
 *
 * Extends the upstream Zephyr gpio_sn74hc595 driver (8 outputs, single
 * register) to a chain of up to four registers sharing one SPI bus and one
 * RCLK latch line (driven as SPI chip-select).
 *
 * Bit mapping matches RMK's Hc595Matrix: pin 0 is QA of the register closest
 * to the MCU, i.e. the lowest state byte is shifted out last.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define DT_DRV_COMPAT onthe15_sn74hc595_chain

#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/kernel.h>
#include <zephyr/device.h>

#include <zephyr/drivers/gpio/gpio_utils.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(gpio_sn74hc595_chain, CONFIG_GPIO_LOG_LEVEL);

struct sn74hc595_chain_config {
	/* gpio_driver_config needs to be first */
	struct gpio_driver_config config;

	struct spi_dt_spec bus;
	uint8_t num_bytes;
};

struct sn74hc595_chain_drv_data {
	/* gpio_driver_data needs to be first */
	struct gpio_driver_data data;

	struct k_mutex lock;
	uint32_t output;
};

static int sn74hc595_chain_write_state(const struct device *dev, uint32_t state)
{
	const struct sn74hc595_chain_config *config = dev->config;
	uint8_t buf[4];

	__ASSERT(!k_is_in_isr(), "attempt to access SPI from ISR");

	/* First byte shifted out ends up in the farthest register, so send
	 * the highest state byte first; the lowest byte lands in the register
	 * closest to the MCU (pins 0-7).
	 */
	for (uint8_t i = 0; i < config->num_bytes; i++) {
		buf[i] = (uint8_t)(state >> (8U * (config->num_bytes - 1U - i)));
	}

	struct spi_buf tx_buf[] = { { .buf = buf, .len = config->num_bytes } };
	const struct spi_buf_set tx = { .buffers = tx_buf, .count = 1 };

	return spi_write_dt(&config->bus, &tx);
}

static int sn74hc595_chain_pin_config(const struct device *dev, gpio_pin_t pin, gpio_flags_t flags)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(pin);

	if ((flags & GPIO_INPUT) != 0U) {
		return -ENOTSUP;
	}

	return 0;
}

static int sn74hc595_chain_port_get_raw(const struct device *dev, uint32_t *value)
{
	struct sn74hc595_chain_drv_data *drv_data = dev->data;

	k_mutex_lock(&drv_data->lock, K_FOREVER);
	*value = drv_data->output;
	k_mutex_unlock(&drv_data->lock);

	return 0;
}

static int sn74hc595_chain_port_set_masked_raw(const struct device *dev, uint32_t mask,
					       uint32_t value)
{
	struct sn74hc595_chain_drv_data *drv_data = dev->data;
	int ret = 0;
	uint32_t output;

	k_mutex_lock(&drv_data->lock, K_FOREVER);

	if ((drv_data->output & mask) != (mask & value)) {
		output = (drv_data->output & ~mask) | (mask & value);

		ret = sn74hc595_chain_write_state(dev, output);
		if (ret == 0) {
			drv_data->output = output;
		}
	}

	k_mutex_unlock(&drv_data->lock);
	return ret;
}

static int sn74hc595_chain_port_set_bits_raw(const struct device *dev, uint32_t mask)
{
	return sn74hc595_chain_port_set_masked_raw(dev, mask, mask);
}

static int sn74hc595_chain_port_clear_bits_raw(const struct device *dev, uint32_t mask)
{
	return sn74hc595_chain_port_set_masked_raw(dev, mask, 0U);
}

static int sn74hc595_chain_port_toggle_bits(const struct device *dev, uint32_t mask)
{
	struct sn74hc595_chain_drv_data *drv_data = dev->data;
	int ret;
	uint32_t output;

	k_mutex_lock(&drv_data->lock, K_FOREVER);

	output = drv_data->output ^ mask;
	ret = sn74hc595_chain_write_state(dev, output);
	if (ret == 0) {
		drv_data->output = output;
	}

	k_mutex_unlock(&drv_data->lock);
	return ret;
}

static int sn74hc595_chain_init(const struct device *dev)
{
	const struct sn74hc595_chain_config *config = dev->config;
	struct sn74hc595_chain_drv_data *drv_data = dev->data;
	int ret;

	if (!spi_is_ready_dt(&config->bus)) {
		LOG_ERR("SPI bus %s not ready", config->bus.bus->name);
		return -ENODEV;
	}

	k_mutex_init(&drv_data->lock);

	/* Drive all outputs low so no matrix column is active at boot. */
	ret = sn74hc595_chain_write_state(dev, 0U);
	if (ret < 0) {
		LOG_ERR("Failed to clear shift register: %d", ret);
		return ret;
	}
	drv_data->output = 0U;

	return 0;
}

static const struct gpio_driver_api sn74hc595_chain_api = {
	.pin_configure = sn74hc595_chain_pin_config,
	.port_get_raw = sn74hc595_chain_port_get_raw,
	.port_set_masked_raw = sn74hc595_chain_port_set_masked_raw,
	.port_set_bits_raw = sn74hc595_chain_port_set_bits_raw,
	.port_clear_bits_raw = sn74hc595_chain_port_clear_bits_raw,
	.port_toggle_bits = sn74hc595_chain_port_toggle_bits,
};

#define SN74HC595_CHAIN_INIT(n)                                                               \
	BUILD_ASSERT(DT_INST_PROP(n, ngpios) % 8 == 0 && DT_INST_PROP(n, ngpios) <= 32,       \
		     "ngpios must be a multiple of 8, at most 32");                           \
	static const struct sn74hc595_chain_config sn74hc595_chain_config_##n = {             \
		.config = {                                                                   \
			.port_pin_mask = GPIO_PORT_PIN_MASK_FROM_DT_INST(n),                  \
		},                                                                            \
		.bus = SPI_DT_SPEC_INST_GET(                                                  \
			n, SPI_OP_MODE_MASTER | SPI_WORD_SET(8) | SPI_TRANSFER_MSB, 0),       \
		.num_bytes = DT_INST_PROP(n, ngpios) / 8,                                     \
	};                                                                                    \
                                                                                              \
	static struct sn74hc595_chain_drv_data sn74hc595_chain_data_##n;                      \
                                                                                              \
	DEVICE_DT_INST_DEFINE(n, sn74hc595_chain_init, NULL, &sn74hc595_chain_data_##n,       \
			      &sn74hc595_chain_config_##n, POST_KERNEL,                       \
			      CONFIG_GPIO_SN74HC595_CHAIN_INIT_PRIORITY,                      \
			      &sn74hc595_chain_api);

DT_INST_FOREACH_STATUS_OKAY(SN74HC595_CHAIN_INIT)
