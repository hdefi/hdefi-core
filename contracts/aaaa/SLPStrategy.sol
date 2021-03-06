// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;
import "./libraries/TransferHelper.sol";
import "./libraries/SafeMath.sol";
import "./modules/BaseShareField.sol";

interface ICollateralStrategy {
    function invest(address user, uint amount) external; 
    function withdraw(address user, uint amount) external;
    function liquidation(address user) external;
    function claim(address user, uint amount, uint total) external;
    function exit(uint amount) external;
    function migrate(address old) external;
    function query() external view returns (uint);
    function mint() external;

    function interestToken() external returns (address);
    function collateralToken() external returns (address);
}

interface IMasterChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
    function poolInfo(uint _index) external view returns(address, uint, uint, uint);
}

contract SLPStrategy is ICollateralStrategy, BaseShareField
{
    event Mint(address indexed user, uint amount);
    using SafeMath for uint;

    address override public interestToken;
    address override public collateralToken;

    address public poolAddress;
    address public masterChef;
    address public old;
    uint public lpPoolpid;

    address public factory;

    constructor() public {
        factory = msg.sender;
    }

    function initialize(address _interestToken, address _collateralToken, address _poolAddress, address _sushiMasterChef, uint _lpPoolpid) public
    {
        require(msg.sender == factory, 'STRATEGY FORBIDDEN');
        interestToken = _interestToken;
        collateralToken = _collateralToken;
        poolAddress = _poolAddress;
        masterChef = _sushiMasterChef;
        lpPoolpid = _lpPoolpid;
        _setShareToken(_interestToken);
    }

    function migrate(address _old) external override 
    {
        require(msg.sender == poolAddress, "INVALID CALLER");
        if(_old != address(0)) {
            uint amount = IERC20(collateralToken).balanceOf(address(this));
            if(amount > 0) {
                IERC20(collateralToken).approve(masterChef, amount);
                IMasterChef(masterChef).deposit(lpPoolpid, amount);
            }

            totalProductivity = BaseShareField(_old).totalProductivity();
            old = _old;
        }
    }

    function invest(address user, uint amount) external override
    {
        _sync(user);

        require(msg.sender == poolAddress, "INVALID CALLER");
        TransferHelper.safeTransferFrom(collateralToken, msg.sender, address(this), amount);
        IERC20(collateralToken).approve(masterChef, amount);
        IMasterChef(masterChef).deposit(lpPoolpid, amount);
        _increaseProductivity(user, amount);
    }

    function withdraw(address user, uint amount) external override
    {
        _sync(user);

        require(msg.sender == poolAddress, "INVALID CALLER");
        IMasterChef(masterChef).withdraw(lpPoolpid, amount);
        TransferHelper.safeTransfer(collateralToken, msg.sender, amount);
        _decreaseProductivity(user, amount);
    }

    function liquidation(address user) external override {
        _sync(user);
        _sync(msg.sender);

        require(msg.sender == poolAddress, "INVALID CALLER");
        uint amount = users[user].amount;
        _decreaseProductivity(user, amount);

        uint reward = users[user].rewardEarn;
        users[msg.sender].rewardEarn = users[msg.sender].rewardEarn.add(reward);
        users[user].rewardEarn = 0;
        _increaseProductivity(msg.sender, amount);
    }

    function claim(address user, uint amount, uint total) external override {
        _sync(msg.sender);

        require(msg.sender == poolAddress, "INVALID CALLER");
        IMasterChef(masterChef).withdraw(lpPoolpid, amount);
        TransferHelper.safeTransfer(collateralToken, msg.sender, amount);
        _decreaseProductivity(msg.sender, amount);
    
        uint claimAmount = users[msg.sender].rewardEarn.mul(amount).div(total);
        users[user].rewardEarn = users[user].rewardEarn.add(claimAmount);
        users[msg.sender].rewardEarn = users[msg.sender].rewardEarn.sub(claimAmount);
    }

    function exit(uint amount) external override {
        require(msg.sender == poolAddress, "INVALID CALLER");
        IMasterChef(masterChef).withdraw(lpPoolpid, amount);
        TransferHelper.safeTransfer(collateralToken, msg.sender, amount);
    }

    function _sync(address user) internal 
    {
        if(old != address(0) && users[user].initialize == false) {
            (uint amount, ) = BaseShareField(old).getProductivity(user);
            users[user].amount = amount;
            users[user].initialize = true;
        } 
    }

    function _currentReward() internal override view returns (uint) {
        return mintedShare.add(IERC20(shareToken).balanceOf(address(this))).add(IMasterChef(masterChef).pendingSushi(lpPoolpid, address(this))).sub(totalShare);
    }

    function query() external override view returns (uint){
        return _takeWithAddress(msg.sender);
    }

    function mint() external override {
        _sync(msg.sender);
        
        IMasterChef(masterChef).deposit(lpPoolpid, 0);
        uint amount = _mint(msg.sender);
        emit Mint(msg.sender, amount);
    }
}