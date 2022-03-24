//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
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

    // Useless starting supply
    uint256 _totalSupply = 10**9 * 10**_decimals;
    
    // balances
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
    
    // Taxation on transfers
    uint256 public buyFee             = 30;
    uint256 public sellFee            = 30;
    uint256 public transferFee        = 30;
    uint256 public constant TAX_DENOM = 1000;

    // Reward Distributor
    IDistributor distributor;

    // Useless Swapper
    address public UselessSwapper;

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
    address public transferFeeRecipient;

    // events
    event SetBuyFeeRecipient(address recipient);
    event SetSellFeeRecipient(address recipient);
    event SetTransferFeeRecipient(address recipient);
    event DistributorUpgraded(address newDistributor);
    event SetUselessSwapper(address newUselessSwapper);
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

    function burn(uint256 amount) external {
        require(
            balanceOf(msg.sender) >= amount && amount > 0,
            'Insufficient Balance'
        );
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint amount) external {
        require(
            balanceOf(account) >= amount && amount > 0,
            'Insufficient Balance'
        );
        require(
            account != address(0),
            'Zero Address'
        );
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, 'Insufficient Allowance');
        _burn(account, amount);
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
        (uint256 fee, address feeRecipient) = getTax(sender, recipient, amount);

        if (fee > 0 && feeRecipient != address(0)) {
            // allocate fee
            _balances[feeRecipient] = _balances[feeRecipient].add(fee);
            emit Transfer(sender, feeRecipient, fee);
        }

        // give amount to recipient
        uint256 sendAmount = amount.sub(fee);
        _balances[recipient] = _balances[recipient].add(sendAmount);

        // set distributor state 
        if (!permissions[sender].rewardsExempt) {
            distributor.setShare(sender, balanceOf(sender));
        }
        if (!permissions[recipient].rewardsExempt) {
            distributor.setShare(recipient, balanceOf(recipient));
        }

        emit Transfer(sender, recipient, sendAmount);
    }

    function withdraw(address token) external onlyOwner {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function withdrawONE() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }

    function setBuyFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        buyFeeRecipient = recipient;
        emit SetBuyFeeRecipient(recipient);
    }

    function setTransferFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        transferFeeRecipient = recipient;
        emit SetTransferFeeRecipient(recipient);
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

    function setUselessSwapper(address newUselessSwapper) external onlyOwner {
        require(newUselessSwapper != address(0), 'Zero Address');
        UselessSwapper = newUselessSwapper;
        emit SetUselessSwapper(newUselessSwapper);
    }

    function registerAutomatedMarketMakerPair(address liquidityPool) external onlyOwner {
        require(liquidityPool != address(0), 'Zero Address');
        require(!permissions[liquidityPool].isLiquidityPool, 'Already An AMM');
        permissions[liquidityPool].isLiquidityPool = true;
        emit SetAutomatedMarketMaker(liquidityPool, true);
    }

    function unRegisterAutomatedMarketMakerPair(address liquidityPool) external onlyOwner {
        require(liquidityPool != address(0), 'Zero Address');
        require(permissions[liquidityPool].isLiquidityPool, 'Not An AMM');
        permissions[liquidityPool].isLiquidityPool = false;
        emit SetAutomatedMarketMaker(liquidityPool, false);
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

    function getTax(address sender, address recipient, uint256 amount) public view returns (uint256, address) {
        if ( permissions[sender].isEgressFeeExempt || permissions[recipient].isIngressFeeExempt ) {
            return (0, address(0));
        }
        return permissions[sender].isLiquidityPool ? 
               (amount.mul(buyFee).div(TAX_DENOM), buyFeeRecipient) : 
               permissions[recipient].isLiquidityPool ? 
               (amount.mul(sellFee).div(TAX_DENOM), sellFeeRecipient) :
               (amount.mul(transferFee).div(TAX_DENOM), transferFeeRecipient);
    }

    receive() external payable {
        (bool s,) = payable(UselessSwapper).call{value: msg.value}("");
        require(s);
    }

    function _burn(address from, uint amount) internal {
        _balances[from] = _balances[from].sub(amount, 'Underflow');
        _totalSupply = _totalSupply.sub(amount, 'Underflow');
    }

}