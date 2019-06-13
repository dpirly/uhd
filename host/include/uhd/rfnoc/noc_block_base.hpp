//
// Copyright 2019 Ettus Research, a National Instruments Brand
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

#ifndef INCLUDED_LIBUHD_NOC_BLOCK_BASE_HPP
#define INCLUDED_LIBUHD_NOC_BLOCK_BASE_HPP

#include <uhd/config.hpp>
#include <uhd/property_tree.hpp>
#include <uhd/rfnoc/block_id.hpp>
#include <uhd/rfnoc/node.hpp>
#include <uhd/rfnoc/register_iface_holder.hpp>
#include <uhd/types/device_addr.hpp>

//! Shorthand for block constructor
#define RFNOC_BLOCK_CONSTRUCTOR(CLASS_NAME) \
    CLASS_NAME##_impl(make_args_ptr make_args) : CLASS_NAME(std::move(make_args))

#define RFNOC_DECLARE_BLOCK(CLASS_NAME) \
    using sptr = std::shared_ptr<CLASS_NAME>;\
    CLASS_NAME(make_args_ptr make_args) : noc_block_base(std::move(make_args)) {}

namespace uhd { namespace rfnoc {

class clock_iface;
class mb_controller;

/*!
 * The primary interface to a NoC block in the FPGA
 *
 * The block supports three types of data access:
 * - Low-level register access
 * - High-level property access
 * - Action execution
 *
 * The main difference between this class and its parent is the direct access to
 * registers, and the NoC&block IDs.
 */
class UHD_API noc_block_base : public node_t, public register_iface_holder
{
public:
    /*! A shared pointer to allow easy access to this class and for
     *  automatic memory management.
     */
    using sptr = std::shared_ptr<noc_block_base>;

    /*! The NoC ID is the unique identifier of the block type. All blocks of the
     * same type have the same NoC ID.
     */
    using noc_id_t = uint32_t;

    //! Forward declaration for the constructor arguments
    struct make_args_t;

    //! Opaque pointer to the constructor arguments
    using make_args_ptr = std::unique_ptr<make_args_t>;

    virtual ~noc_block_base();

    /**************************************************************************
     * node_t API calls
     *************************************************************************/
    //! Unique ID for an RFNoC block is its block ID
    std::string get_unique_id() const { return get_block_id().to_string(); }

    //! Number of input ports. Note: This gets passed into this block from the
    // information stored in the global register space.
    //
    // Note: This may be overridden by the block (e.g., the X300 radio may not
    // have all ports available if no TwinRX board is plugged in), but the
    // subclassed version may never report more ports than this.
    size_t get_num_input_ports() const { return _num_input_ports; }

    //! Number of output ports. Note: This gets passed outto this block from the
    // information stored in the global register space.
    //
    // Note: This may be overridden by the block (e.g., the X300 radio may not
    // have all ports available if no TwinRX board is plugged in), but the
    // subclassed version may never report more ports than this.
    size_t get_num_output_ports() const { return _num_output_ports; }

    /**************************************************************************
     * RFNoC-block specific API calls
     *************************************************************************/
    /*! Return the NoC ID for this block.
     *
     * \return noc_id The 32-bit NoC ID of this block
     */
    noc_id_t get_noc_id() const { return _noc_id; }

    /*! Returns the unique block ID for this block.
     *
     * \return block_id The block ID of this block (e.g. "0/FFT#1")
     */
    const block_id_t& get_block_id() const { return _block_id; }

    /*! Returns the tick rate of the current time base
     *
     * Note there is only ever one time base (or tick rate) per block.
     */
    double get_tick_rate() const { return _tick_rate; }

    /*! Return the arguments that were passed into this block from the framework
     */
    uhd::device_addr_t get_block_args() const { return _block_args; }

    //! Return a reference to this block's subtree
    uhd::property_tree::sptr& get_tree() const { return _tree; }

    //! Return a reference to this block's subtree (non-const version)
    uhd::property_tree::sptr& get_tree() { return _tree; }

protected:
    noc_block_base(make_args_ptr make_args);

    //! Update number of input ports.
    //
    // - The new number of ports may not exceed the old number. This can only
    //   be used to 'decrease' the number of ports.
    // - This is considered an 'advanced' API and should rarely be called by
    //   blocks. See also get_num_output_ports().
    //
    // \throws uhd::value_error if \p num_ports is larger than the current
    //         number of ports.
    void set_num_input_ports(const size_t num_ports);

    //! Update number of output ports.
    //
    // - The new number of ports may not exceed the old number. This can only
    //   be used to 'decrease' the number of ports.
    // - This is considered an 'advanced' API and should rarely be called by
    //   blocks. An example of where this is useful is the X310 radio block,
    //   which has 2 output ports, but only 1 is useful for UBX/SBX/WBX boards
    //   (i.e., boards with 1 frontend). In that case, software can make a
    //   determination to 'invalidate' one of the ports.
    //
    // \throws uhd::value_error if \p num_ports is larger than the current
    //         number of ports.
    void set_num_output_ports(const size_t num_ports);

    /*! Update tick rate for this node and all the connected nodes
     *
     * Careful: Calling this function will trigger a property propagation to any
     * block this block is connected to.
     */
    void set_tick_rate(const double tick_rate);

    /*! Get access to the motherboard controller for this block's motherboard
     *
     * This will return a nullptr if this block doesn't have access to the
     * motherboard. In order to gain access to the motherboard, the block needs
     * to have requested access to the motherboard during the registration
     * procedure. See also registry.hpp.
     *
     * Even if this block requested access to the motherboard controller, there
     * is no guarantee that UHD will honour that request. It is therefore
     * important to verify that the returned pointer is valid.
     */
    std::shared_ptr<mb_controller> get_mb_controller();

    /*! Safely de-initialize the block
     *
     * This function is called by the framework when the RFNoC session is about
     * to finish to allow blocks to safely perform actions to shut down a block.
     * For example, if your block is producing samples, like a radio or signal
     * generator, this is a good place to issue a "stop" command.
     *
     * After this function is called, register access is no more possible. So
     * make sure not to interact with regs() after this was called. Future
     * access to regs() won't throw, but will print error messages and do
     * nothing.
     *
     * The rationale for having this separate from the destructor is because
     * rfnoc_graph allows exporting references to blocks, and this function
     * ensures that blocks are safely shut down when the rest of the device
     * control goes away.
     */
    virtual void deinit();

private:
    /*! Update the tick rate of this block
     *
     * This will make sure that the underlying register_iface is notified of the
     * change in timebase.
     */
    void _set_tick_rate(const double tick_rate);

    /*! Perform a shutdown sequence.
     *
     * - Call deinit()
     * - Invalidate regs()
     */
    void shutdown();

    /**************************************************************************
     * Attributes
     **************************************************************************/
    //! This block's Noc-ID
    noc_id_t _noc_id;

    //! This block's block-ID
    //
    // The framework will guarantee that no one else has the same block ID
    block_id_t _block_id;

    //! Number of input ports
    size_t _num_input_ports;

    //! Number of output ports
    size_t _num_output_ports;

    //! Container for the 'tick rate' property. This will hold one edge property
    // for all in- and output edges.
    std::vector<property_t<double>> _tick_rate_props;

    //! The actual tick rate of the current time base
    double _tick_rate;

    //! Reference to the clock_iface object shared with the register_iface
    std::shared_ptr<clock_iface> _clock_iface;

    //! Stores a reference to this block's motherboard's controller, if this
    // block had requested and was granted access
    std::shared_ptr<mb_controller> _mb_controller;

    //! Arguments that were passed into this block
    const uhd::device_addr_t _block_args;

    //! Reference to this block's subtree
    //
    // It is mutable because _tree->access<>(..).get() is not const, but we
    // need to do just that in some const contexts
    mutable uhd::property_tree::sptr _tree;

}; // class noc_block_base

}} /* namespace uhd::rfnoc */

#include <uhd/rfnoc/noc_block_make_args.hpp>

#endif /* INCLUDED_LIBUHD_NOC_BLOCK_BASE_HPP */