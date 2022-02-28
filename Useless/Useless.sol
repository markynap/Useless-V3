//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";
import "./SafeMath.sol";

interface IDistributor {
    function setShare(address shareholder, uint256 amount) external;
}

contract Useless is IERC20, Ownable {

    using SafeMath for uint256;

    // total supply
    uint256 private _totalSupply;

    // token data
    string constant _name = "Useless";
    string constant _symbol = "USE";
    uint8 constant _decimals = 18;

    // 10 xUSD Starting Supply
    uint256 _totalSupply = 10**9 * 10**_decimals;
    
    // balances
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    // PCS Router
    IUniswapV2Router02 router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address[] path;

    // Taxation on transfers
    uint256 public buyFee             = 30;
    uint256 public sellFee            = 30;
    uint256 public transferFee        = 30;
    uint256 public constant TAX_DENOM = 1000;

    // reward distributor
    IDistributor distributor;

    // permissions
    struct Permissions {
        bool isIngressFeeExempt;
        uint256 ingressExemptIndex;
        bool isEgressFeeExempt;
        uint256 egressExemptIndex;
        bool rewardsExempt;
        bool isLiquidityPool;
    }
    mapping ( address => Permissions ) permissions;

    // ingress and egress exemption arrays for transparency
    address[] public ingressExemptContracts;
    address[] public egressExemptContracts;

    // Fee Recipients
    address public sellFeeRecipient;
    address public buyFeeRecipient;

    // events
    event SetBuyFeeRecipient(address recipient);
    event SetSellFeeRecipient(address recipient);
    event DistributorUpgraded(address newDistributor);
    event SetRewardsExempt(address account, bool isExempt);
    event SetEgressExemption(address account, bool isEgressExempt);
    event SetIngressExemption(address account, bool isIngressExempt);
    event SetAutomatedMarketMaker(address account, bool isMarketMaker);
    event SetFees(uint256 buyFee, uint256 sellFee, uint256 transferFee);
    
    // modifiers
    modifier onlyOwner(){
        require(msg.sender == owner, 'Only Owner');
        _;
    }

    constructor(address distributor) {
        // dividends distributor
        distributor = IDistributor(distributor);
        
        // swapper info
        path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(this);

        // Set initial automated market maker
        permissions[
            IUniswapV2Factory(router.factory()).createPair(router.WETH(), address(this))
        ].isLiquidityPool = true;

        // initial supply allocation
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    
    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
  
    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, 'Insufficient Allowance');
        return _transferFrom(sender, recipient, amount);
    }
    
    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(
            recipient != address(0),
            'Zero Recipient'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= balanceOf(sender),
            'Insufficient Balance'
        );
        
        // decrement sender balance
        _balances[sender] = _balances[sender].sub(amount);
        // fee for transaction
        uint256 fee = getTax(sender, recipient, amount);

        if (fee > 0) {
            // allocate fee
            address recipient = permissions[recipient].isLiquidityPool ? sellFeeRecipient : buyFeeRecipient;
            _balances[recipient] = _balances[recipient].add(fee);
            emit Transfer(sender, recipient, fee);
        }

        // give amount to recipient
        uint256 sendAmount = amount.sub(fee);
        _balances[recipient] = _balances[recipient].add(sendAmount);

        // set distributor state 
        if (!permissions[sender].rewardsExempt) {
            distributor.setShare(sender, balanceOf(sender));
        }
        if (!permissions[recipient].rewardsExempt) {
            distributor.setShare(sender, balanceOf(sender));
        }

        emit Transfer(sender, recipient, sendAmount);
    }

    function withdraw(address token) external onlyOwner {
        IERC20(token).transfer(owner, IERC20(token).balanceOf(address(this)));
    }

    function withdrawBNB() external onlyOwner {
        _sendBNB(owner, address(this).balance);
    }

    function setBuyFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        buyFeeRecipient = recipient;
        emit SetBuyFeeRecipient(recipient);
    }

    function setSellFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        sellFeeRecipient = recipient;
        emit SetSellFeeRecipient(recipient);
    }

    function upgradeDistributor(address newDistributor) external onlyOwner {
        require(newDistributor != address(0), 'Zero Address');
        distributor = IDistributor(newDistributor);
        emit DistributorUpgraded(newDistributor);
    }

    function registerAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(!permissions[account].isLiquidityPool, 'Already An AMM');
        permissions[account].isLiquidityPool = true;
        emit SetAutomatedMarketMaker(account, true);
    }

    function unRegisterAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(permissions[account].isLiquidityPool, 'Not An AMM');
        permissions[account].isLiquidityPool = false;
        emit SetAutomatedMarketMaker(account, false);
    }

    function setFees(uint _buyFee, uint _sellFee, uint _transferFee) external onlyOwner {
        require(
            buyFee <= TAX_DENOM.div(10),
            'Buy Fee Too High'
        );
        require(
            buyFee <= TAX_DENOM.div(10),
            'Sell Fee Too High'
        );
        require(
            buyFee <= TAX_DENOM.div(10),
            'Transfer Fee Too High'
        );

        buyFee = _buyFee;
        sellFee = _sellFee;
        transferFee = _transferFee;

        emit SetFees(_buyFee, _sellFee, _transferFee);
    }

    function setRewardsExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].rewardsExempt = isExempt;

        if (isExempt) {
            distributor.setShare(account, 0);
        } else {
            distributor.setShare(account, balanceOf(account));
        }
        emit SetRewardsExempt(account, isExempt);
    }

    function DisableIngressTaxation(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(!permissions[account].isIngressExempt, 'Already Disabled');

        // set tax exemption
        permissions[account].isIngressExempt = true;
        permissions[account].ingressExemptIndex = ingressExemptContracts.length;
        // add to transparency array
        ingressExemptContracts.push(account);
        
        emit SetIngressExemption(account, true);
    }

    function EnableIngressTaxation(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(permissions[account].isIngressExempt, 'Account Not Disabled');
        require(
            ingressExemptContracts[permissions[account].ingressExemptIndex] == account,
            'Account Does Not Match Index'
        );
        
        // set index of last element to be removal index
        permissions[
            ingressExemptContracts[ingressExemptContracts.length - 1]
        ].ingressExemptIndex = permissions[account].ingressExemptIndex;
        // set position of removal index to be last element of array
        ingressExemptContracts[
            permissions[account].ingressExemptIndex
        ] = ingressExemptContracts[ingressExemptContracts.length - 1];
        // pop duplicate off the end of the array
        ingressExemptContracts.pop();
        // disable tax exemption
        permissions[account].isIngressExempt = false;
        permissions[account].ingressExemptIndex = 0;

        emit SetIngressExemption(account, false);
    }

    function DisableEgressTaxation(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(!permissions[account].isEgressExempt, 'Already Disabled');

        // set tax exemption
        permissions[account].isEgressExempt = true;
        permissions[account].egressExemptIndex = egressExemptContracts.length;
        // add to transparency array
        egressExemptContracts.push(account);
        
        emit SetEgressExemption(account, true);
    }

    function EnableEgressTaxation(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(permissions[account].isEgressExempt, 'Account Not Disabled');
        require(
            egressExemptContracts[permissions[account].egressExemptIndex] == account,
            'Account Does Not Match Index'
        );
        
        // set index of last element to be removal index
        permissions[
            egressExemptContracts[egressExemptContracts.length - 1]
        ].egressExemptIndex = permissions[account].egressExemptIndex;
        // set position of removal index to be last element of array
        egressExemptContracts[
            permissions[account].egressExemptIndex
        ] = egressExemptContracts[egressExemptContracts.length - 1];
        // pop duplicate off the end of the array
        egressExemptContracts.pop();
        // disable tax exemption
        permissions[account].isEgressExempt = false;
        permissions[account].egressExemptIndex = 0;

        emit SetEgressExemption(account, false);
    }

    function getTax(address sender, address recipient, uint256 amount) public view returns (uint256) {
        if ( permissions[sender].isEgressFeeExempt || permissions[recipient].isIngressFeeExempt ) {
            return 0;
        }
        return permissions[sender].isLiquidityPool ? 
               amount.mul(buyFee).div(TAX_DENOM) : 
               permissions[recipient].isLiquidityPool ? 
               amount.mul(sellFee).div(TAX_DENOM) :
               amount.mul(transferFee).div(TAX_DENOM);
    }

    receive() external payable {
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(0, path, msg.sender, block.timestamp + 300);
    }

    function _sendBNB(address recipient, uint256 amount) internal {
        (bool s,) = payable(recipient).call{value: amount}("");
        require(s);
    }
}