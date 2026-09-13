if(CONFIG_GPIO_SN74HC595_CHAIN)
  zephyr_library()
  zephyr_library_sources(gpio_sn74hc595_chain.c)
endif()
