// SPDX-License-Identifier: MIT

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.13;
pragma experimental ABIEncoderV2;

import "./interfaces/IFlashCallback.sol";

import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./lib/ABDKMath64x64.sol";

import "./lib/FullMath.sol";

import "./lib/NoDelegateCall.sol";

import "./Orchestrator.sol";

import "./ProportionalLiquidity.sol";

import "./Swaps.sol";

import "./ViewLiquidity.sol";

import "./Storage.sol";

import "./interfaces/IFreeFromUpTo.sol";

import "./interfaces/ICurveFactory.sol";

import "./Structs.sol";

library Curves {
    using ABDKMath64x64 for int128;

    event Approval(
        address indexed _owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function add(
        uint256 x,
        uint256 y,
        string memory errorMessage
    ) private pure returns (uint256 z) {
        require((z = x + y) >= x, errorMessage);
    }

    function sub(
        uint256 x,
        uint256 y,
        string memory errorMessage
    ) private pure returns (uint256 z) {
        require((z = x - y) <= x, errorMessage);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(
        Storage.Curve storage curve,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        _transfer(curve, msg.sender, recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(
        Storage.Curve storage curve,
        address spender,
        uint256 amount
    ) external returns (bool) {
        _approve(curve, msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20};
     *
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for `sender`'s tokens of at least
     * `amount`
     */
    function transferFrom(
        Storage.Curve storage curve,
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        _transfer(curve, sender, recipient, amount);
        _approve(
            curve,
            sender,
            msg.sender,
            sub(
                curve.allowances[sender][msg.sender],
                amount,
                "Curve/insufficient-allowance"
            )
        );
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(
        Storage.Curve storage curve,
        address spender,
        uint256 addedValue
    ) external returns (bool) {
        _approve(
            curve,
            msg.sender,
            spender,
            add(
                curve.allowances[msg.sender][spender],
                addedValue,
                "Curve/approval-overflow"
            )
        );
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(
        Storage.Curve storage curve,
        address spender,
        uint256 subtractedValue
    ) external returns (bool) {
        _approve(
            curve,
            msg.sender,
            spender,
            sub(
                curve.allowances[msg.sender][spender],
                subtractedValue,
                "Curve/allowance-decrease-underflow"
            )
        );
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is public function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        Storage.Curve storage curve,
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        curve.balances[sender] = sub(
            curve.balances[sender],
            amount,
            "Curve/insufficient-balance"
        );
        curve.balances[recipient] = add(
            curve.balances[recipient],
            amount,
            "Curve/transfer-overflow"
        );
        emit Transfer(sender, recipient, amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `_owner`s tokens.
     *
     * This is public function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `_owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        Storage.Curve storage curve,
        address _owner,
        address spender,
        uint256 amount
    ) private {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        curve.allowances[_owner][spender] = amount;
        emit Approval(_owner, spender, amount);
    }
}

contract Curve is Storage, NoDelegateCall {
    using SafeMath for uint256;
    using ABDKMath64x64 for int128;
    using SafeERC20 for IERC20;

    address private curveFactory;

    event Approval(
        address indexed _owner,
        address indexed spender,
        uint256 value
    );

    event ParametersSet(
        uint256 alpha,
        uint256 beta,
        uint256 delta,
        uint256 epsilon,
        uint256 lambda
    );

    event AssetIncluded(
        address indexed numeraire,
        address indexed reserve,
        uint256 weight
    );

    event AssimilatorIncluded(
        address indexed derivative,
        address indexed numeraire,
        address indexed reserve,
        address assimilator
    );

    event PartitionRedeemed(
        address indexed token,
        address indexed redeemer,
        uint256 value
    );

    event OwnershipTransfered(
        address indexed previousOwner,
        address indexed newOwner
    );

    event FrozenSet(bool isFrozen);

    event EmergencyAlarm(bool isEmergency);

    event Trade(
        address indexed trader,
        address indexed origin,
        address indexed target,
        uint256 originAmount,
        uint256 targetAmount,
        int128 rawProtocolFee
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Flash(
        address indexed from,
        address indexed to,
        uint256 value0,
        uint256 value1,
        uint256 paid0,
        uint256 paid1
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Curve/caller-is-not-owner");
        _;
    }

    modifier nonReentrant() {
        require(notEntered, "Curve/re-entered");
        notEntered = false;
        _;
        notEntered = true;
    }

    modifier transactable() {
        require(!frozen, "Curve/frozen-only-allowing-proportional-withdraw");
        _;
    }

    modifier isEmergency() {
        require(
            emergency,
            "Curve/emergency-only-allowing-emergency-proportional-withdraw"
        );
        _;
    }

    modifier isNotEmergency() {
        require(
            !emergency,
            "Curve/emergency-only-allowing-emergency-proportional-withdraw"
        );
        _;
    }

    modifier deadline(uint256 _deadline) {
        require(block.timestamp < _deadline, "Curve/tx-deadline-passed");
        _;
    }

    modifier globallyTransactable() {
        require(
            !ICurveFactory(address(curveFactory)).getGlobalFrozenState(),
            "Curve/frozen-globally-only-allowing-proportional-withdraw"
        );
        _;
    }

    modifier isFlashable() {
        require(
            ICurveFactory(address(curveFactory)).getFlashableState(),
            "Curve/flashloans-paused"
        );
        _;
    }

    modifier isDepositable(address pool, uint256 deposits) {
        {
            uint256 poolCap = ICurveFactory(curveFactory).getPoolCap(pool);
            uint256 supply = totalSupply();
            require(
                poolCap == 0 || supply.add(deposits) <= poolCap,
                "curve/exceeds pool cap"
            );
        }
        if (!ICurveFactory(curveFactory).isPoolGuarded(pool)) {
            _;
        } else {
            _;
            uint256 poolGuardAmt = ICurveFactory(curveFactory).getPoolGuardAmount(pool);
            require(curve.balances[msg.sender] <= poolGuardAmt, "curve/deposit-exceeds-guard-amt");
        }
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address[] memory _assets,
        uint256[] memory _assetWeights,
        address _factory
    ) {
        require(_factory != address(0), "Curve/curve factory zero address!");
        owner = msg.sender;
        name = _name;
        symbol = _symbol;
        curveFactory = _factory;
        emit OwnershipTransfered(address(0), msg.sender);

        Orchestrator.initialize(
            curve,
            numeraires,
            reserves,
            derivatives,
            _assets,
            _assetWeights
        );
    }

    /// @notice sets the parameters for the pool
    /// @param _alpha the value for alpha (halt threshold) must be less than or equal to 1 and greater than 0
    /// @param _beta the value for beta must be less than alpha and greater than 0
    /// @param _feeAtHalt the maximum value for the fee at the halt point
    /// @param _epsilon the base fee for the pool
    /// @param _lambda the value for lambda must be less than or equal to 1 and greater than zero
    function setParams(
        uint256 _alpha,
        uint256 _beta,
        uint256 _feeAtHalt,
        uint256 _epsilon,
        uint256 _lambda
    ) external onlyOwner {
        Orchestrator.setParams(
            curve,
            _alpha,
            _beta,
            _feeAtHalt,
            _epsilon,
            _lambda
        );
    }

    function setAssimilator(
        address _baseCurrency,
        address _baseAssim,
        address _quoteCurrency,
        address _quoteAssim
    ) external onlyOwner {
        Orchestrator.setAssimilator(
            curve,
            _baseCurrency,
            _baseAssim,
            _quoteCurrency,
            _quoteAssim
        );
    }

    /// @notice excludes an assimilator from the curve
    /// @param _derivative the address of the assimilator to exclude
    function excludeDerivative(address _derivative) external onlyOwner {
        for (uint256 i = 0; i < numeraires.length; i++) {
            if (_derivative == numeraires[i])
                revert("Curve/cannot-delete-numeraire");
            if (_derivative == reserves[i])
                revert("Curve/cannot-delete-reserve");
        }

        delete curve.assimilators[_derivative];
    }

    /// @notice view the current parameters of the curve
    /// @return alpha_ the current alpha value
    ///  beta_ the current beta value
    ///  delta_ the current delta value
    ///  epsilon_ the current epsilon value
    ///  lambda_ the current lambda value
    ///  omega_ the current omega value
    function viewCurve()
        external
        view
        returns (
            uint256 alpha_,
            uint256 beta_,
            uint256 delta_,
            uint256 epsilon_,
            uint256 lambda_
        )
    {
        return Orchestrator.viewCurve(curve);
    }

    function setEmergency(bool _emergency) external onlyOwner {
        emit EmergencyAlarm(_emergency);

        emergency = _emergency;
    }

    function setFrozen(bool _toFreezeOrNotToFreeze) external onlyOwner {
        emit FrozenSet(_toFreezeOrNotToFreeze);

        frozen = _toFreezeOrNotToFreeze;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        require(
            _newOwner != address(0),
            "Curve/new-owner-cannot-be-zeroth-address"
        );

        emit OwnershipTransfered(owner, _newOwner);

        owner = _newOwner;
    }

    /// @notice swap a dynamic origin amount for a fixed target amount
    /// @param _origin the address of the origin
    /// @param _target the address of the target
    /// @param _originAmount the origin amount
    /// @param _minTargetAmount the minimum target amount
    /// @param _deadline deadline in block number after which the trade will not execute
    /// @return targetAmount_ the amount of target that has been swapped for the origin amount
    function originSwap(
        address _origin,
        address _target,
        uint256 _originAmount,
        uint256 _minTargetAmount,
        uint256 _deadline
    )
        external
        deadline(_deadline)
        globallyTransactable
        transactable
        noDelegateCall
        isNotEmergency
        nonReentrant
        returns (uint256 targetAmount_)
    {
        OriginSwapData memory _swapData;
        _swapData._origin = _origin;
        _swapData._target = _target;
        _swapData._originAmount = _originAmount;
        _swapData._recipient = msg.sender;
        _swapData._curveFactory = curveFactory;
        targetAmount_ = Swaps.originSwap(curve, _swapData);
        // targetAmount_ = Swaps.originSwap(curve, _origin, _target, _originAmount, msg.sender,curveFactory);

        require(
            targetAmount_ >= _minTargetAmount,
            "Curve/below-min-target-amount"
        );
    }

    /// @notice view how much target amount a fixed origin amount will swap for
    /// @param _origin the address of the origin
    /// @param _target the address of the target
    /// @param _originAmount the origin amount
    /// @return targetAmount_ the target amount that would have been swapped for the origin amount
    function viewOriginSwap(
        address _origin,
        address _target,
        uint256 _originAmount
    )
        external
        view
        globallyTransactable
        transactable
        returns (uint256 targetAmount_)
    {
        targetAmount_ = Swaps.viewOriginSwap(
            curve,
            _origin,
            _target,
            _originAmount
        );
    }

    /// @notice swap a dynamic origin amount for a fixed target amount
    /// @param _origin the address of the origin
    /// @param _target the address of the target
    /// @param _maxOriginAmount the maximum origin amount
    /// @param _targetAmount the target amount
    /// @param _deadline deadline in block number after which the trade will not execute
    /// @return originAmount_ the amount of origin that has been swapped for the target
    function targetSwap(
        address _origin,
        address _target,
        uint256 _maxOriginAmount,
        uint256 _targetAmount,
        uint256 _deadline
    )
        external
        deadline(_deadline)
        globallyTransactable
        transactable
        noDelegateCall
        isNotEmergency
        nonReentrant
        returns (uint256 originAmount_)
    {
        TargetSwapData memory _swapData;
        _swapData._origin = _origin;
        _swapData._target = _target;
        _swapData._targetAmount = _targetAmount;
        _swapData._recipient = msg.sender;
        _swapData._curveFactory = curveFactory;
        originAmount_ = Swaps.targetSwap(curve, _swapData);
        // originAmount_ = Swaps.targetSwap(curve, _origin, _target, _targetAmount, msg.sender,curveFactory);

        require(
            originAmount_ <= _maxOriginAmount,
            "Curve/above-max-origin-amount"
        );
    }

    /// @notice view how much of the origin currency the target currency will take
    /// @param _origin the address of the origin
    /// @param _target the address of the target
    /// @param _targetAmount the target amount
    /// @return originAmount_ the amount of target that has been swapped for the origin
    function viewTargetSwap(
        address _origin,
        address _target,
        uint256 _targetAmount
    )
        external
        view
        globallyTransactable
        transactable
        returns (uint256 originAmount_)
    {
        originAmount_ = Swaps.viewTargetSwap(
            curve,
            _origin,
            _target,
            _targetAmount
        );
    }
 
    /// @notice deposit into the pool with no slippage from the numeraire assets the pool supports
    /// @param  _deposit the full amount you want to deposit into the pool which will be divided up evenly amongst
    ///                  the numeraire assets of the pool
    /// @return ( the amount of curves you receive in return for your deposit,
    ///           the amount deposited for each numeraire)
    function deposit(uint256 _deposit,uint256 _minQuoteAmount,uint256 _minBaseAmount,uint256 _maxQuoteAmount, uint256 _maxBaseAmount, uint256 _deadline)
        external
        deadline(_deadline)
        globallyTransactable
        transactable
        nonReentrant
        noDelegateCall
        isNotEmergency
        isDepositable(address(this), _deposit)
        returns (uint256, uint256[] memory)
    {
        require(_deposit >0, "Curve/deposit_below_zero");
        
        // (curvesMinted_,  deposits_)
        DepositData memory _depositData;
        _depositData.deposits = _deposit;
        _depositData.minQuote = _minQuoteAmount;
        _depositData.minBase = _minBaseAmount;
        _depositData.maxQuote = _maxQuoteAmount;
        _depositData.maxBase = _maxBaseAmount;
        (
            uint256 curvesMinted_,
            uint256[] memory deposits_
        ) = ProportionalLiquidity.proportionalDeposit(curve, _depositData);
        return (curvesMinted_, deposits_);
    }

    /// @notice view deposits and curves minted a given deposit would return
    /// @param _deposit the full amount of stablecoins you want to deposit. Divided evenly according to the
    ///                 prevailing proportions of the numeraire assets of the pool
    /// @return (the amount of curves you receive in return for your deposit,
    ///          the amount deposited for each numeraire)
    function viewDeposit(uint256 _deposit)
        external
        view
        globallyTransactable
        transactable
        returns (uint256, uint256[] memory)
    {
        // curvesToMint_, depositsToMake_
        return ProportionalLiquidity.viewProportionalDeposit(curve, _deposit);
    }

    /// @notice  Emergency withdraw tokens in the event that the oracle somehow bugs out
    ///          and no one is able to withdraw due to the invariant check
    /// @param   _curvesToBurn the full amount you want to withdraw from the pool which will be withdrawn from evenly amongst the
    ///                        numeraire assets of the pool
    /// @return withdrawals_ the amonts of numeraire assets withdrawn from the pool
    function emergencyWithdraw(uint256 _curvesToBurn, uint256 _deadline)
        external
        isEmergency
        deadline(_deadline)
        nonReentrant
        noDelegateCall
        returns (uint256[] memory withdrawals_)
    {
        return ProportionalLiquidity.proportionalWithdraw(curve, _curvesToBurn);
    }

    /// @notice  withdrawas amount of curve tokens from the the pool equally from the numeraire assets of the pool with no slippage
    /// @param   _curvesToBurn the full amount you want to withdraw from the pool which will be withdrawn from evenly amongst the
    ///                        numeraire assets of the pool
    /// @return withdrawals_ the amonts of numeraire assets withdrawn from the pool
    function withdraw(uint256 _curvesToBurn, uint256 _deadline)
        external
        deadline(_deadline)
        nonReentrant
        noDelegateCall
        isNotEmergency
        returns (uint256[] memory withdrawals_)
    {
        return ProportionalLiquidity.proportionalWithdraw(curve, _curvesToBurn);
    }

    /// @notice  views the withdrawal information from the pool
    /// @param   _curvesToBurn the full amount you want to withdraw from the pool which will be withdrawn from evenly amongst the
    ///                        numeraire assets of the pool
    /// @return the amonnts of numeraire assets withdrawn from the pool
    function viewWithdraw(uint256 _curvesToBurn)
        external
        view
        globallyTransactable
        transactable
        returns (uint256[] memory)
    {
        return
            ProportionalLiquidity.viewProportionalWithdraw(
                curve,
                _curvesToBurn
            );
    }

    function supportsInterface(bytes4 _interface)
        public
        pure
        returns (bool supports_)
    {
        supports_ =
            this.supportsInterface.selector == _interface || // erc165
            bytes4(0x7f5828d0) == _interface || // eip173
            bytes4(0x36372b07) == _interface; // erc20
    }

    /// @notice transfers curve tokens
    /// @param _recipient the address of where to send the curve tokens
    /// @param _amount the amount of curve tokens to send
    /// @return success_ the success bool of the call
    function transfer(address _recipient, uint256 _amount)
        public
        nonReentrant
        noDelegateCall
        isNotEmergency
        returns (bool success_)
    {
        success_ = Curves.transfer(curve, _recipient, _amount);
    }

    /// @notice transfers curve tokens from one address to another address
    /// @param _sender the account from which the curve tokens will be sent
    /// @param _recipient the account to which the curve tokens will be sent
    /// @param _amount the amount of curve tokens to transfer
    /// @return success_ the success bool of the call
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    )
        public
        nonReentrant
        noDelegateCall
        isNotEmergency
        returns (bool success_)
    {
        success_ = Curves.transferFrom(curve, _sender, _recipient, _amount);
    }

    /// @notice approves a user to spend curve tokens on their behalf
    /// @param _spender the account to allow to spend from msg.sender
    /// @param _amount the amount to specify the spender can spend
    /// @return success_ the success bool of this call
    function approve(address _spender, uint256 _amount)
        public
        nonReentrant
        noDelegateCall
        returns (bool success_)
    {
        success_ = Curves.approve(curve, _spender, _amount);
    }

    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    )
        external
        isFlashable
        globallyTransactable
        nonReentrant
        noDelegateCall
        transactable
        isNotEmergency
    {
        uint256 fee = curve.epsilon.mulu(1e18);

        require(
            IERC20(derivatives[0]).balanceOf(address(this)) > 0,
            "Curve/token0-zero-liquidity-depth"
        );
        require(
            IERC20(derivatives[1]).balanceOf(address(this)) > 0,
            "Curve/token1-zero-liquidity-depth"
        );

        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e18);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e18);

        uint256 balance0Before = IERC20(derivatives[0]).balanceOf(
            address(this)
        );
        uint256 balance1Before = IERC20(derivatives[1]).balanceOf(
            address(this)
        );

        if (amount0 > 0)
            IERC20(derivatives[0]).safeTransfer(recipient, amount0);
        if (amount1 > 0)
            IERC20(derivatives[1]).safeTransfer(recipient, amount1);

        IFlashCallback(msg.sender).flashCallback(fee0, fee1, data);

        uint256 balance0After = IERC20(derivatives[0]).balanceOf(address(this));
        uint256 balance1After = IERC20(derivatives[1]).balanceOf(address(this));

        require(
            balance0Before.add(fee0) <= balance0After,
            "Curve/insufficient-token0-returned"
        );
        require(
            balance1Before.add(fee1) <= balance1After,
            "Curve/insufficient-token1-returned"
        );

        // sub is safe because we know balanceAfter is gt balanceBefore by at least fee
        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        IERC20(derivatives[0]).safeTransfer(owner, paid0);
        IERC20(derivatives[1]).safeTransfer(owner, paid1);

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    /// @notice view the curve token balance of a given account
    /// @param _account the account to view the balance of
    /// @return balance_ the curve token ballance of the given account
    function balanceOf(address _account)
        public
        view
        returns (uint256 balance_)
    {
        balance_ = curve.balances[_account];
    }

    /// @notice views the total curve supply of the pool
    /// @return totalSupply_ the total supply of curve tokens
    function totalSupply() public view returns (uint256 totalSupply_) {
        totalSupply_ = curve.totalSupply;
    }

    /// @notice views the total allowance one address has to spend from another address
    /// @param _owner the address of the owner
    /// @param _spender the address of the spender
    /// @return allowance_ the amount the owner has allotted the spender
    function allowance(address _owner, address _spender)
        public
        view
        returns (uint256 allowance_)
    {
        allowance_ = curve.allowances[_owner][_spender];
    }

    /// @notice views the total amount of liquidity in the curve in numeraire value and format - 18 decimals
    /// @return total_ the total value in the curve
    /// @return individual_ the individual values in the curve
    function liquidity()
        public
        view
        returns (uint256 total_, uint256[] memory individual_)
    {
        return ViewLiquidity.viewLiquidity(curve);
    }

    /// @notice view the assimilator address for a derivative
    /// @return assimilator_ the assimilator address
    function assimilator(address _derivative)
        public
        view
        returns (address assimilator_)
    {
        assimilator_ = curve.assimilators[_derivative].addr;
    }
}
