//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";

contract StakingContract is Ownable {

    using SafeMath for uint256;

    // lock time in blocks
    uint256 public lockTime = 201600;

    // fee for leaving staking early
    uint256 public leaveEarlyFee = 3;

    // recipient of fee
    address public feeRecipient;

    // Useless Token
    address public immutable token;

    // BUSD for liquidating rewards
    address public immutable BUSD;

    // DEX Router For Swapping
    IUniswapV2Router02 private router;

    // User Info
    struct UserInfo {
        uint256 amount;
        uint256 unlockBlock;
        uint256 totalExcluded;
    }
    // Address => UserInfo
    mapping ( address => UserInfo ) public userInfo;

    // Tracks Dividends
    uint256 public totalShares;
    uint256 private dividendsPerShare;
    uint256 private constant precision = 10**18;

    // Swap Paths
    address[] busdPath;
    address[] nativePath;

    event SetDEX(address DEX_);
    event SetLockTime(uint LockTime);
    event SetEarlyFee(uint earlyFee);
    event SetFeeRecipient(address FeeRecipient);

    constructor(address BUSD_, address token_, address DEX){
        require(
            BUSD_ != address(0) &&
            token_ != address(0) &&
            DEX != address(0),
            'Zero Address'
        );

        token = token_;
        BUSD = BUSD_;
        router = IUniswapV2Router02(DEX);

        // BUSD -> Useless
        busdPath = new address[](2);
        busdPath[0] = BUSD_;
        busdPath[1] = router.WETH();
        busdPath[2] = token_;

        // Native -> Useless
        nativePath = new address[](2);
        nativePath[0] = router.WETH();
        nativePath[1] = token_;
    }

    function setDEX(address DEX_) external onlyOwner {
        require(
            DEX_ != address(0),
            'Zero Address'
        );
        router = IUniswapV2Router02(DEX_);
        emit SetDEX(DEX_);
    }

    function setLockTime(uint256 newLockTime) external onlyOwner {
        require(
            lockTime <= 10**7,
            'Lock Time Too Long'
        );
        lockTime = newLockTime;
        emit SetLockTime(newLockTime);
    }

    function setLeaveEarlyFee(uint256 newEarlyFee) external onlyOwner {
        require(
            newEarlyFee <= 10,
            'Fee Too High'
        );
        leaveEarlyFee = newEarlyFee;
        emit SetEarlyFee(newEarlyFee);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(
            newFeeRecipient != address(0),
            'Zero Address'
        );
        feeRecipient = newFeeRecipient;
        emit SetFeeRecipient(newFeeRecipient);
    }

    function withdraw(address token_) external onlyOwner {
        require(
            token != token_ && BUSD != token_,
            'Cannot Withdraw Useless Or BUSD'
        );
        require(
            IERC20(token_).transfer(
                msg.sender,
                IERC20(token_).balanceOf(address(this))
            ),
            'Failure On Token Withdraw'
        );
    }

    

    function claimRewards() external {
        _claimReward(msg.sender);
    }

    function convertBUSDToUseless() external {
        // Approve Router For BUSD Swap
        uint bal = IERC20(BUSD).balanceOf(address(this));
        IERC20(BUSD).approve(address(router), bal);

        // Swap BUSD For USELESS
        uint before = IERC20(token).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(bal, 0, busdPath, address(this), block.timestamp + 300);
        uint received = IERC20(token).balanceOf(address(this)) - before;

        // Add Received Useless To Rewards
        dividendsPerShare = dividendsPerShare.add(precision.mul(received).div(totalShares));
    }

    function withdraw(uint256 amount) external {
        require(
            amount <= userInfo[msg.sender].amount,
            'Insufficient Amount'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        if (userInfo[msg.sender].amount > 0) {
            _claimReward(msg.sender);
        }

        totalShares -= amount;
        userInfo[msg.sender].amount -= amount;
        userInfo[msg.sender].totalExcluded = getCumulativeDividends(userInfo[msg.sender].amount);

        uint fee = timeUntilUnlock(msg.sender) == 0 ? 0 : ( amount * leaveEarlyFee ) / 100;
        if (fee > 0) {
            require(
                IERC20(token).transfer(feeRecipient, fee),
                'Failure On Token Transfer'
            );
        }

        uint sendAmount = amount - fee;
        require(
            IERC20(token).transfer(msg.sender, sendAmount),
            'Failure On Token Transfer To Sender'
        );
    }

    function stake(uint256 amount) external {
        if (userInfo[msg.sender].amount > 0) {
            _claimReward(msg.sender);
        }

        // transfer in tokens
        uint received = _transferIn(amount);
        
        // update data
        totalShares += received;
        userInfo[msg.sender].amount += received;
        userInfo[msg.sender].unlockBlock = block.number + lockTime;
        userInfo[msg.sender].totalExcluded = getCumulativeDividends(userInfo[msg.sender].amount);
    }

    function deposit(uint256 amount) external {
        uint received = _transferIn(amount);
        dividendsPerShare = dividendsPerShare.add(precision.mul(received).div(totalShares));
    }




    function _claimReward(address user) internal {

        // exit if zero value locked
        if (userInfo[user].amount == 0) {
            return;
        }

        // fetch pending rewards
        uint256 amount = pendingRewards(user);
        
        // exit if zero rewards
        if (amount == 0) {
            return;
        }

        // update total excluded
        userInfo[msg.sender].totalExcluded = getCumulativeDividends(userInfo[msg.sender].amount);

        // transfer reward to user
        require(
            IERC20(token).transfer(user, amount),
            'Failure On Token Claim'
        );
    }

    function _transferIn(uint256 amount) internal returns (uint256) {
        uint before = IERC20(token).balanceOf(address(this));
        bool s = IERC20(token).transferFrom(msg.sender, address(this), amount);
        uint received = IERC20(token).balanceOf(address(this)) - before;
        require(
            s && received > 0 && received <= amount,
            'Error On Transfer From'
        );
        return received;
    }



    function timeUntilUnlock(address user) public view returns (uint256) {
        return userInfo[user].unlockBlock < block.number ? 0 : userInfo[user].unlockBlock - block.number;
    }

    function pendingRewards(address shareholder) public view returns (uint256) {
        if(userInfo[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(userInfo[shareholder].amount);
        uint256 shareholderTotalExcluded = userInfo[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function balanceOf(address user) external view returns (uint256) {
        return userInfo[user].amount;
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(precision);
    }



    receive() external payable {
        // Swap Native For USELESS
        uint before = IERC20(token).balanceOf(address(this));
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(0, nativePath, address(this), block.timestamp + 300);
        uint received = IERC20(token).balanceOf(address(this)) - before;

        // Add Received Useless To Rewards
        dividendsPerShare = dividendsPerShare.add(precision.mul(received).div(totalShares));
    }

}