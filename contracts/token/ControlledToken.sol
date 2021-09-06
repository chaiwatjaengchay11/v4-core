// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./ControlledTokenInterface.sol";

/// @title Controlled ERC20 Token
/// @notice ERC20 Tokens with a controller for minting & burning
contract ControlledToken is ERC20PermitUpgradeable, ControlledTokenInterface {

  /// @dev Emitted when an instance is initialized
  event Initialized(
    string _name,
    string _symbol,
    uint8 _decimals,
    address _controller
  );

  /// @notice Interface to the contract responsible for controlling mint/burn
  address public override controller;

  /// @notice ERC20 controlled token decimals.
  uint8 private _decimals;

  /// @notice Initializes the Controlled Token with Token Details and the Controller
  /// @param _name The name of the Token
  /// @param _symbol The symbol for the Token
  /// @param decimals_ The number of decimals for the Token
  /// @param _controller Address of the Controller contract for minting & burning
  function initialize(
    string memory _name,
    string memory _symbol,
    uint8 decimals_,
    address _controller
  )
    public
    virtual
    initializer
  {
    require(address(_controller) != address(0), "ControlledToken/controller-not-zero");
    controller = _controller;

    __ERC20_init(_name, _symbol);
    __ERC20Permit_init("PoolTogether ControlledToken");
    _decimals = decimals_;

    emit Initialized(
      _name,
      _symbol,
      _decimals,
      _controller
    );
  }

  /// @notice Allows the controller to mint tokens for a user account
  /// @dev May be overridden to provide more granular control over minting
  /// @param _user Address of the receiver of the minted tokens
  /// @param _amount Amount of tokens to mint
  function controllerMint(address _user, uint256 _amount) external virtual override onlyController {
    _mint(_user, _amount);
  }

  /// @notice Allows the controller to burn tokens from a user account
  /// @dev May be overridden to provide more granular control over burning
  /// @param _user Address of the holder account to burn tokens from
  /// @param _amount Amount of tokens to burn
  function controllerBurn(address _user, uint256 _amount) external virtual override onlyController {
    _burn(_user, _amount);
  }

  /// @notice Allows an operator via the controller to burn tokens on behalf of a user account
  /// @dev May be overridden to provide more granular control over operator-burning
  /// @param _operator Address of the operator performing the burn action via the controller contract
  /// @param _user Address of the holder account to burn tokens from
  /// @param _amount Amount of tokens to burn
  function controllerBurnFrom(address _operator, address _user, uint256 _amount) external virtual override onlyController {
    if (_operator != _user) {
      uint256 decreasedAllowance = allowance(_user, _operator) - _amount;
      _approve(_user, _operator, decreasedAllowance);
    }
    _burn(_user, _amount);
  }

  /// @notice Returns the ERC20 controlled token decimals.
  /// @dev This value should be equal to the decimals of the token used to deposit into the pool.
  /// @return uint8 decimals.
  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }

  /// @dev Function modifier to ensure that the caller is the controller contract
  modifier onlyController {
    require(_msgSender() == address(controller), "ControlledToken/only-controller");
    _;
  }
}
