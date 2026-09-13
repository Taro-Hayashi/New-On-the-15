/* SPDX-License-Identifier: MIT */

#define DT_DRV_COMPAT onthe15_battery_nimh_diagnostic

#include <errno.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/init.h>

#include "battery_curve.h"
#include "battery_settings.h"

#define VOLTAGE_AVERAGE_SAMPLES 3

/*
 * Panasonic BK-4MCC typical 160 mA discharge curve at 25 C, after a one-hour
 * rest. Remaining capacity is derived from the 750 mAh minimum capacity and
 * linearly interpolated between these digitized points.
 * https://files.batteryjunction.com/frontend/files/Panasonic-Eneloop-BK-4MC.pdf
 */

struct battery_diagnostic_config {
  const struct device *adc;
  uint8_t channel;
  uint32_t output_ohms;
  uint32_t full_ohms;
  uint8_t series_cell_count;
};

struct battery_diagnostic_data {
  struct adc_channel_cfg channel_cfg;
  struct adc_sequence sequence;
  int16_t adc_raw;
  uint16_t millivolts;
  uint8_t state_of_charge;
  uint16_t voltage_samples[VOLTAGE_AVERAGE_SAMPLES];
  uint32_t voltage_sum;
  uint8_t voltage_sample_count;
  uint8_t voltage_sample_index;
};

static int battery_diagnostic_sample_fetch(const struct device *dev,
                                           enum sensor_channel chan) {
  struct battery_diagnostic_data *data = dev->data;
  const struct battery_diagnostic_config *config = dev->config;

  if (chan != SENSOR_CHAN_GAUGE_VOLTAGE &&
      chan != SENSOR_CHAN_GAUGE_STATE_OF_CHARGE && chan != SENSOR_CHAN_ALL) {
    return -ENOTSUP;
  }

  int rc = adc_read(config->adc, &data->sequence);
  data->sequence.calibrate = false;
  if (rc < 0) {
    return rc;
  }

  int32_t sense_mv = data->adc_raw;
  rc = adc_raw_to_millivolts(adc_ref_internal(config->adc),
                             data->channel_cfg.gain, data->sequence.resolution,
                             &sense_mv);
  if (rc < 0) {
    return rc;
  }

  if (sense_mv < 0) {
    return -EIO;
  }

  const uint16_t measured_mv =
      sense_mv * (uint64_t)config->full_ohms / config->output_ohms;

  if (data->voltage_sample_count == VOLTAGE_AVERAGE_SAMPLES) {
    data->voltage_sum -= data->voltage_samples[data->voltage_sample_index];
  } else {
    data->voltage_sample_count++;
  }
  data->voltage_samples[data->voltage_sample_index] = measured_mv;
  data->voltage_sum += measured_mv;
  data->voltage_sample_index =
      (data->voltage_sample_index + 1) % VOLTAGE_AVERAGE_SAMPLES;
  data->millivolts = data->voltage_sum / data->voltage_sample_count;

  const uint16_t cell_mv = data->millivolts / config->series_cell_count;
  data->state_of_charge = onthe15_battery_state_of_charge(onthe15_battery_type_get(), cell_mv);
  return 0;
}

static int battery_diagnostic_channel_get(const struct device *dev,
                                          enum sensor_channel chan,
                                          struct sensor_value *value) {
  const struct battery_diagnostic_data *data = dev->data;

  switch (chan) {
  case SENSOR_CHAN_GAUGE_VOLTAGE:
    value->val1 = data->millivolts / 1000;
    value->val2 = (data->millivolts % 1000) * 1000;
    return 0;
  case SENSOR_CHAN_GAUGE_STATE_OF_CHARGE:
    value->val1 = data->state_of_charge;
    value->val2 = 0;
    return 0;
  default:
    return -ENOTSUP;
  }
}

static const struct sensor_driver_api battery_diagnostic_api = {
    .sample_fetch = battery_diagnostic_sample_fetch,
    .channel_get = battery_diagnostic_channel_get,
};

static int battery_diagnostic_init(const struct device *dev) {
  struct battery_diagnostic_data *data = dev->data;
  const struct battery_diagnostic_config *config = dev->config;

  if (!device_is_ready(config->adc)) {
    return -ENODEV;
  }

  if (config->series_cell_count == 0) {
    return -EINVAL;
  }

  data->channel_cfg = (struct adc_channel_cfg){
      .gain = ADC_GAIN_1_6,
      .reference = ADC_REF_INTERNAL,
      .acquisition_time = ADC_ACQ_TIME(ADC_ACQ_TIME_MICROSECONDS, 40),
      .input_positive = SAADC_CH_PSELP_PSELP_AnalogInput0 + config->channel,
  };
  data->sequence = (struct adc_sequence){
      .channels = BIT(0),
      .buffer = &data->adc_raw,
      .buffer_size = sizeof(data->adc_raw),
      .resolution = 12,
      .oversampling = 4,
      .calibrate = true,
  };

  return adc_channel_setup(config->adc, &data->channel_cfg);
}

static struct battery_diagnostic_data battery_diagnostic_data;
static const struct battery_diagnostic_config battery_diagnostic_config = {
    .adc = DEVICE_DT_GET(DT_IO_CHANNELS_CTLR(DT_DRV_INST(0))),
    .channel = DT_IO_CHANNELS_INPUT(DT_DRV_INST(0)),
    .output_ohms = DT_INST_PROP(0, output_ohms),
    .full_ohms = DT_INST_PROP(0, full_ohms),
    .series_cell_count = DT_INST_PROP(0, series_cell_count),
};

DEVICE_DT_INST_DEFINE(0, battery_diagnostic_init, NULL,
                      &battery_diagnostic_data, &battery_diagnostic_config,
                      POST_KERNEL, CONFIG_SENSOR_INIT_PRIORITY,
                      &battery_diagnostic_api);
