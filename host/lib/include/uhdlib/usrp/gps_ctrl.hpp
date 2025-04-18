//
// Copyright 2010-2011,2014 Ettus Research LLC
// Copyright 2018 Ettus Research, a National Instruments Company
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

#pragma once

#include <uhd/types/sensors.hpp>
#include <uhd/types/serial.hpp>
#include <uhd/utils/noncopyable.hpp>
#include <memory>
#include <vector>

namespace uhd {

class gps_ctrl : uhd::noncopyable
{
public:
    typedef std::shared_ptr<gps_ctrl> sptr;

    virtual ~gps_ctrl(void) = 0;

    /*!
     * Make a GPS config for internal GPSDOs or generic NMEA GPS devices
     */
    static sptr make(uart_iface::sptr uart);

    /*!
     * Retrieve the list of sensors this GPS object provides
     */
    virtual std::vector<std::string> get_sensors(void) = 0;

    /*!
     * Retrieve the named sensor
     */
    virtual uhd::sensor_value_t get_sensor(std::string key) = 0;

    /*!
     * Tell you if there's a supported GPS connected or not
     * \return true if a supported GPS is connected
     */
    virtual bool gps_detected(void) = 0;

    /*! Send arbitrary command to the GPS device.
     *
     * Using this can cause the GPS to enter an unknown state, so use with
     * caution. It is up to the user to identify correct and valid commands.
     *
     * \return The response from the GPS device
     */
    virtual std::string send_cmd(std::string cmd) = 0;
};

} // namespace uhd
