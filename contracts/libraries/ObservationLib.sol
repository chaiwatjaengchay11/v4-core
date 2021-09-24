// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./OverflowSafeComparator.sol";
import "./RingBuffer.sol";

/// @title Time-Weighted Average Balance Library
/// @notice This library allows you to efficiently track a user's historic balance.  You can get a
/// @author PoolTogether Inc.
library ObservationLib {
  using OverflowSafeComparator for uint32;
  using SafeCast for uint256;

  /// @notice The maximum number of observation entries
  uint16 public constant MAX_CARDINALITY = 65535;

  /// @notice Time Weighted Average Balance (Observation).
  /// @param amount `amount` at `timestamp`.
  /// @param timestamp Recorded `timestamp`.
  struct Observation {
    uint224 amount;
    uint32 timestamp;
  }

  /// @notice Fetches Observations `beforeOrAt` and `atOrAfter` a `_target`, eg: where [`beforeOrAt`, `atOrAfter`] is satisfied.
  /// The result may be the same Observation, or adjacent Observations.
  /// @dev The answer must be contained in the array, used when the target is located within the stored Observation.
  /// boundaries: older than the most recent Observation and younger, or the same age as, the oldest Observation.
  /// @param _observations List of Observations to search through.
  /// @param _observationIndex Index of the Observation to start searching from.
  /// @param _target Timestamp at which the reserved Observation should be for.
  /// @return beforeOrAt Observation recorded before, or at, the target.
  /// @return atOrAfter Observation recorded at, or after, the target.
  function binarySearch(
    Observation[MAX_CARDINALITY] storage _observations,
    uint16 _observationIndex,
    uint16 _oldestObservationIndex,
    uint32 _target,
    uint16 _cardinality,
    uint32 _time
  ) internal view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
    uint256 leftSide = _oldestObservationIndex; // Oldest Observation
    uint256 rightSide = _observationIndex < leftSide ? leftSide + _cardinality - 1 : _observationIndex;
    uint256 currentIndex;

    while (true) {
      currentIndex = (leftSide + rightSide) / 2;
      beforeOrAt = _observations[uint16(RingBuffer.wrap(currentIndex, _cardinality))];
      uint32 beforeOrAtTimestamp = beforeOrAt.timestamp;

      // We've landed on an uninitialized timestamp, keep searching higher (more recently)
      if (beforeOrAtTimestamp == 0) {
        leftSide = currentIndex + 1;
        continue;
      }

      atOrAfter = _observations[uint16(RingBuffer.nextIndex(currentIndex, _cardinality))];

      bool targetAtOrAfter = beforeOrAtTimestamp.lte(_target, _time);

      // Check if we've found the corresponding Observation
      if (targetAtOrAfter && _target.lte(atOrAfter.timestamp, _time)) {
        break;
      }

      // If `beforeOrAtTimestamp` is greater than `_target`, then we keep searching lower
      if (!targetAtOrAfter) rightSide = currentIndex - 1;

      // Otherwise, we keep searching higher
      else leftSide = currentIndex + 1;
    }
  }

}