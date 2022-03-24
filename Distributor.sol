//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./SafeMath.sol";
import "./Address.sol";
import "./IUniswapV2Router02.sol";
import "./IERC20.sol";
import "./ReentrantGuard.sol";

/** Distributes Tokens To Useless Holders Based On Weight */
contract Distributor is ReentrancyGuard {
    
    using SafeMath for uint256;
    using Address for address;
    
    // Useless Contract
    address public _token;
    
    // Share of Vault
    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        address rewardToken;
    }
    
    // Reward Token
    struct RewardToken {
        bool isApproved;
        address dexRouter;
        uint256 index;
    }
    
    // Reward Tokens
    mapping (address => RewardToken) rewardTokens;
    address[] allRewardTokens;
    
    // Main Contract Address
    address public main;

    // Pancakeswap Router
    address public immutable v2router;
    
    // shareholder fields
    address[] shareholders;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;
    mapping (address => Share) public shares;
    
    // shares math and fields
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public dividendsPerShare;
    uint256 constant dividendsPerShareAccuracyFactor = 10 ** 18;

    // auto claim every hour if able
    uint256 public constant minAutoPeriod = 1200;

    // owner of token contract - used to pair with Vault Token
    address _tokenOwner;

    modifier onlyToken() {
        require(msg.sender == _token); _;
    }
    
    modifier onlyTokenOwner() {
        require(msg.sender == _tokenOwner, 'Invalid Entry'); _;
    }

    constructor (address _router, address _busd) {
        // Set Router
        v2router = _router;
        // BUSD
        _approveTokenForSwap(_busd);
        // BUSD is Main
        main = _busd;
        // Distributor master 
        _tokenOwner = msg.sender;
    }
    
    ///////////////////////////////////////////////
    //////////      Only Token Owner    ///////////
    ///////////////////////////////////////////////

    function setUseless(address USELESS) external onlyTokenOwner {
        require(_token == address(0) && USELESS != address(0), 'Already Paired');
        _token = USELESS;
    }

    function approveTokenForSwap(address token) external onlyTokenOwner {
        require(!rewardTokens[token].isApproved, 'Already Approved');
        _approveTokenForSwap(token, v2router);
        emit ApproveTokenForSwapping(token);
    }
    
    function approveTokenForSwapCustomRouter(address token, address router) external onlyTokenOwner {
        _approveTokenForSwap(token, router);
        emit ApproveTokenForSwapping(token);
    }
    
    function removeTokenFromSwap(address token) external onlyTokenOwner {

        rewardTokens[
            allRewardTokens[allRewardTokens.length - 1]
        ].index = rewardTokens[token].index;

        allRewardTokens[
            rewardTokens[token].index
        ] = allRewardTokens[allRewardTokens.length - 1];
        allRewardTokens.pop();
        
        delete rewardTokens[token];
        emit RemovedTokenForSwapping(token);
    }
    
    function transferTokenOwnership(address newOwner) external onlyTokenOwner {
        _tokenOwner = newOwner;
        emit TransferedTokenOwnership(newOwner);
    }
    
    /** Upgrades To New Distributor */
    function upgradeDistributor(address newDistributor) external onlyTokenOwner {
        require(newDistributor != address(this) && newDistributor != address(0), 'Invalid Input');
        emit UpgradeDistributor(newDistributor);
        if (address(this).balance > 0) {
            (bool s,) = payable(_tokenOwner).call{value: address(this).balance}("");
            require(s);
        }
    }
    
    ///////////////////////////////////////////////
    //////////    Only Token Contract   ///////////
    ///////////////////////////////////////////////
    
    /** Sets Share For User */
    function setShare(address shareholder, uint256 amount) external onlyToken {
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }

        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }
    
    ///////////////////////////////////////////////
    //////////      Public Functions    ///////////
    ///////////////////////////////////////////////
    
    function claimDividendInDesiredToken(address desiredToken) external nonReentrant{
        address previous = getRewardTokenForHolder(msg.sender);
        _setRewardTokenForHolder(msg.sender, desiredToken);
        _claimDividend(msg.sender);
        _setRewardTokenForHolder(msg.sender, previous);
    }
    
    function claimDividendForUser(address shareholder) external nonReentrant {
        _claimDividend(shareholder);
    }
    
    function claimDividend() external nonReentrant {
        _claimDividend(msg.sender);
    }
    
    function setRewardTokenForHolder(address token) external {
        _setRewardTokenForHolder(msg.sender, token);
    }


    ///////////////////////////////////////////////
    //////////    Internal Functions    ///////////
    ///////////////////////////////////////////////


    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
        emit AddedShareholder(shareholder);
    }

    function removeShareholder(address shareholder) internal { 
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder]; 
        shareholders.pop();
        delete shareholderIndexes[shareholder];
        emit RemovedShareholder(shareholder);
    }
    
    function _setRewardTokenForHolder(address holder, address token) private {
        uint256 minimum = IERC20(_token).totalSupply().div(10**5);
        require(shares[holder].amount >= minimum, 'Sender Balance Too Small');
        require(rewardTokens[token].isApproved, 'Token Not Approved');
        shares[holder].rewardToken = token;
        emit SetRewardTokenForHolder(holder, token);
    }
    
    function _approveTokenForSwap(address token, address router) private {
        rewardTokens[token] = RewardToken({
            isApproved: true,
            dexRouter: router,
            index: allRewardTokens.length;
        });
        allRewardTokens.push(token);
    }

    function distributeDividend(address shareholder) internal nonReentrant {
        if(shares[shareholder].amount == 0){ return; }
        uint256 amount = getUnpaidMainEarnings(shareholder);
        address token = getRewardTokenForHolder(shareholder);
        if(amount > 0 && rewardTokens[token].isApproved){
            buyTokenForHolder(token, shareholder, amount);
        }
    }
    
    function buyTokenForHolder(address token, address shareholder, uint256 amount) private {
        if (token == address(0) || shareholder == address(0) || amount == 0) return;
        
        // shareholder claim
        shareholderClaims[shareholder] = block.number;
        
        // set total excluded
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);

        // router
        IUniswapV2Router02 router = IUniswapV2Router02(rewardTokens[token].dexRouter);
        
        // Swap on PCS
        address[] memory mainPath = new address[](2);
        mainPath[0] = router.WETH();
        mainPath[1] = token;
        
        // swap for token
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value:amount}(
            0,
            mainPath,
            shareholder,
            block.timestamp + 300
        );
    }
    
    function _claimDividend(address shareholder) private {
        require(shareholderClaims[shareholder] + minAutoPeriod < block.number, 'Timeout');
        require(shares[shareholder].amount > 0, 'Zero Balance');
        uint256 amount = getUnpaidMainEarnings(shareholder);
        require(amount > 0, 'Zero Amount Owed');
        // update shareholder data
        address token = getRewardTokenForHolder(shareholder);
        buyTokenForHolder(token, shareholder, amount);
    }
    
    ///////////////////////////////////////////////
    //////////      Read Functions      ///////////
    ///////////////////////////////////////////////

    function getShareholders() external view returns (address[] memory) {
        return shareholders;
    }
    
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function getShareForHolder(address holder) external view returns(uint256) {
        return shares[holder].amount;
    }

    function getUnpaidMainEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }
    
    function getRewardTokenForHolder(address holder) public view returns (address) {
        return shares[holder].rewardToken == address(0) ? main : shares[holder].rewardToken;
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }
    
    function isTokenApprovedForSwapping(address token) external view returns (bool) {
        return rewardTokens[token].isApproved;
    }
    
    function getNumShareholders() external view returns(uint256) {
        return shareholders.length;
    }

    // EVENTS 
    event ApproveTokenForSwapping(address token);
    event RemovedTokenForSwapping(address token);
    event UpgradeDistributor(address newDistributor);
    event AddedShareholder(address shareholder);
    event RemovedShareholder(address shareholder);
    event TransferedTokenOwnership(address newOwner);
    event SetRewardTokenForHolder(address holder, address desiredRewardToken);

    receive() external payable {
        // update main dividends
        totalDividends = totalDividends.add(msg.value);
        dividendsPerShare = dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(msg.value).div(totalShares));
    }

}
