// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";

import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBufferLib.sol";
import "./interfaces/IPrizeDistributionHistory.sol";

/**
  * @title  PoolTogether V4 PrizeDistributionHistory
  * @author PoolTogether Inc Team
  * @notice The PrizeDistributionHistory stores historic PrizeDistribution for each drawId.
            Storage of the PrizeDistributions is handled by a ring buffer with a max cardinality
            of 256 or roughly 5 years of history with a weekly draw cadence.
*/
contract PrizeDistributionHistory is IPrizeDistributionHistory, Manageable {
    using DrawRingBufferLib for DrawRingBufferLib.Buffer;

    /// @notice The maximum cardinality of the prize distribution ring buffer.
    /// @dev even with daily draws, 256 will give us over 8 months of history.
    uint256 internal constant MAX_CARDINALITY = 256;

    /// @notice The ceiling for prize distributions.  1e9 = 100%.
    /// @dev It's fixed point 9 because 1e9 is the largest "1" that fits into 2**32
    uint256 internal constant TIERS_CEILING = 1e9;

    /// @notice Emitted when the contract is deployed.
    /// @param cardinality The maximum number of records in the buffer before they begin to expire.
    event Deployed(uint8 cardinality);

    /// @notice PrizeDistribution ring buffer history.
    DrawLib.PrizeDistribution[MAX_CARDINALITY] internal prizeDistributionRingBuffer;

    /// @notice Ring buffer metadata (nextIndex, lastId, cardinality)
    DrawRingBufferLib.Buffer internal bufferMetadata;

    /* ============ Constructor ============ */

    /**
     * @notice Constructor for PrizeDistributionHistory
     * @param _owner Address of the PrizeDistributionHistory owner
     * @param _cardinality Cardinality of the `bufferMetadata`
     */
    constructor(address _owner, uint8 _cardinality) Ownable(_owner) {
        bufferMetadata.cardinality = _cardinality;
        emit Deployed(_cardinality);
    }

    /* ============ External Functions ============ */

    /// @inheritdoc IPrizeDistributionHistory
    function getPrizeDistribution(uint32 _drawId)
        external
        view
        override
        returns (DrawLib.PrizeDistribution memory)
    {
        return _getPrizeDistribution(bufferMetadata, _drawId);
    }

    /// @inheritdoc IPrizeDistributionHistory
    function getPrizeDistributions(uint32[] calldata _drawIds)
        external
        view
        override
        returns (DrawLib.PrizeDistribution[] memory)
    {
        DrawRingBufferLib.Buffer memory buffer = bufferMetadata;
        DrawLib.PrizeDistribution[] memory _prizeDistributions = new DrawLib.PrizeDistribution[](
            _drawIds.length
        );

        for (uint256 i = 0; i < _drawIds.length; i++) {
            _prizeDistributions[i] = _getPrizeDistribution(buffer, _drawIds[i]);
        }

        return _prizeDistributions;
    }

    /// @inheritdoc IPrizeDistributionHistory
    function getPrizeDistributionCount() external view override returns (uint32) {
        DrawRingBufferLib.Buffer memory buffer = bufferMetadata;

        if (buffer.lastDrawId == 0) {
            return 0;
        }

        uint32 bufferNextIndex = buffer.nextIndex;

        // If the buffer is full return the cardinality, else retun the nextIndex
        if (prizeDistributionRingBuffer[bufferNextIndex].matchCardinality != 0) {
            return buffer.cardinality;
        } else {
            return bufferNextIndex;
        }
    }

    /// @inheritdoc IPrizeDistributionHistory
    function getNewestPrizeDistribution()
        external
        view
        override
        returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId)
    {
        DrawRingBufferLib.Buffer memory buffer = bufferMetadata;

        return (
            prizeDistributionRingBuffer[buffer.getIndex(buffer.lastDrawId)],
            buffer.lastDrawId
        );
    }

    /// @inheritdoc IPrizeDistributionHistory
    function getOldestPrizeDistribution()
        external
        view
        override
        returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId)
    {
        DrawRingBufferLib.Buffer memory buffer = bufferMetadata;

        // if the ring buffer is full, the oldest is at the nextIndex
        prizeDistribution = prizeDistributionRingBuffer[buffer.nextIndex];

        // The PrizeDistribution at index 0 IS by default the oldest prizeDistribution.
        if (buffer.lastDrawId == 0) {
            drawId = 0; // return 0 to indicate no prizeDistribution ring buffer history
        } else if (prizeDistribution.bitRangeSize == 0) {
            // IF the next PrizeDistribution.bitRangeSize == 0 the ring buffer HAS NOT looped around so the oldest is the first entry.
            prizeDistribution = prizeDistributionRingBuffer[0];
            drawId = (buffer.lastDrawId + 1) - buffer.nextIndex;
        } else {
            // Calculates the drawId using the ring buffer cardinality
            // Sequential drawIds are gauranteed by DrawRingBufferLib.push()
            drawId = (buffer.lastDrawId + 1) - buffer.cardinality;
        }
    }

    /// @inheritdoc IPrizeDistributionHistory
    function pushPrizeDistribution(
        uint32 _drawId,
        DrawLib.PrizeDistribution calldata _prizeDistribution
    ) external override onlyManagerOrOwner returns (bool) {
        return _pushPrizeDistribution(_drawId, _prizeDistribution);
    }

    /// @inheritdoc IPrizeDistributionHistory
    function setPrizeDistribution(
        uint32 _drawId,
        DrawLib.PrizeDistribution calldata _prizeDistribution
    ) external override onlyOwner returns (uint32) {
        DrawRingBufferLib.Buffer memory buffer = bufferMetadata;
        uint32 index = buffer.getIndex(_drawId);
        prizeDistributionRingBuffer[index] = _prizeDistribution;

        emit PrizeDistributionSet(_drawId, _prizeDistribution);

        return _drawId;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Gets the PrizeDistributionHistory for a drawId
     * @param _buffer DrawRingBufferLib.Buffer
     * @param _drawId drawId
     */
    function _getPrizeDistribution(DrawRingBufferLib.Buffer memory _buffer, uint32 _drawId)
        internal
        view
        returns (DrawLib.PrizeDistribution memory)
    {
        return prizeDistributionRingBuffer[_buffer.getIndex(_drawId)];
    }

    /**
     * @notice Set newest PrizeDistributionHistory in ring buffer storage.
     * @param _drawId       drawId
     * @param _prizeDistribution PrizeDistributionHistory struct
     */
    function _pushPrizeDistribution(
        uint32 _drawId,
        DrawLib.PrizeDistribution calldata _prizeDistribution
    ) internal returns (bool) {

        require(_drawId > 0, "DrawCalc/draw-id-gt-0");
        require(_prizeDistribution.matchCardinality > 0, "DrawCalc/matchCardinality-gt-0");
        require(
            _prizeDistribution.bitRangeSize <= 256 / _prizeDistribution.matchCardinality,
            "DrawCalc/bitRangeSize-too-large"
        );

        require(_prizeDistribution.bitRangeSize > 0, "DrawCalc/bitRangeSize-gt-0");
        require(_prizeDistribution.maxPicksPerUser > 0, "DrawCalc/maxPicksPerUser-gt-0");

        // ensure that the sum of the tiers are not gt 100% and record number of non-zero tiers entries
        uint256 sumTotalTiers = 0;
        uint256 nonZeroTiers = 0;
        uint256 tiersLength = _prizeDistribution.tiers.length;

        for (uint256 index = 0; index < tiersLength; index++) {
            sumTotalTiers += _prizeDistribution.tiers[index];

            if (_prizeDistribution.tiers[index] > 0) {
                nonZeroTiers++;
            }
        }

        // Each tier amount stored as uint32 - summed can't exceed 1e9
        require(sumTotalTiers <= TIERS_CEILING, "DrawCalc/tiers-gt-100%");

        require(
            _prizeDistribution.matchCardinality >= nonZeroTiers,
            "DrawCalc/matchCardinality-gte-tiers"
        );

        DrawRingBufferLib.Buffer memory buffer = bufferMetadata;

        // store the PrizeDistribution in the ring buffer
        prizeDistributionRingBuffer[buffer.nextIndex] = _prizeDistribution;

        // update the ring buffer data
        bufferMetadata = buffer.push(_drawId);

        emit PrizeDistributionSet(_drawId, _prizeDistribution);

        return true;
    }
}
