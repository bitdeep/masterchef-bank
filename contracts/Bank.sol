// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import "./libs/SafeMath.sol";
import "./libs/IERC20.sol";
import "./libs/SafeERC20.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./libs/Ownable.sol";
import "./libs/ReentrancyGuard.sol";
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

contract Bank2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    struct UserInfo {
        uint amount;
        uint rewardDebt;//usdc debt
        uint lastwithdraw;
        uint[] pids;
    }

    struct PoolInfo {
        uint initamt;
        uint amount;
        uint startTime;
        uint endTime;
        uint tokenPerSec;//X10^18
        uint accPerShare;
        IERC20 token;
        uint lastRewardTime;
        address router;
        bool disableCompound;//in case of error
    }

    struct UserPInfo {
        uint rewardDebt;
    }

    struct UsdcPool {
        //usdcPerSec everyweek
        uint idx;
        uint[] wkUnit; //weekly usdcPerSec. 4week cycle
        uint usdcPerTime;//*1e18
        uint startTime;
        uint accUsdcPerShare;
        uint lastRewardTime;
    }

    /**Variables */

    mapping(address => UserInfo) public userInfo;
    PoolInfo[] public poolInfo;
    mapping(uint => bool) public skipPool;//in case of stuck in one token.
    mapping(uint => mapping(address => UserPInfo)) public userPInfo;
    address[] public lotlist;
    uint public lotstart = 1;
    UsdcPool public usdcPool;
    IERC20 public APOLLO;
    IERC20 public USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IERC20 public wmatic = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address public apollorouter = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;//quickswap
    address public devaddr;
    address public winner;
    address public lotwinner;
    uint public winnum;
    uint public totalAmount;
    uint public newRepo;
    uint public currentRepo;
    uint public period;
    uint public endtime;
    uint public totalpayout;
    uint public entryMin = 5 ether; //min APOLLO to enroll lotterypot
    uint public lotsize;
    uint public lotrate = 200;//bp of total prize.
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    uint public totalBurnt;
    bool public paused;
    mapping(address => bool) public approvedContracts;
    modifier onlyApprovedContractOrEOA() {
        require(
            tx.origin == msg.sender || approvedContracts[msg.sender],
            "onlyApprovedContractOrEOA"
        );
        _;
    }
    constructor(IERC20 _lp) public {
        APOLLO = IERC20(_lp);
        paused = true;
        usdcPool.wkUnit = [0, 0, 0, 0];
        devaddr = address(msg.sender);
        wmatic.approve(apollorouter, uint(- 1));
        USDC.approve(apollorouter, uint(- 1));
        lotlist.push(burnAddress);
    }
    modifier ispaused(){
        require(paused == false, "paused");
        _;
    }

    /**View functions  */
    function userinfo(address _user) public view returns (UserInfo memory){
        return userInfo[_user];
    }

    function usdcinfo() public view returns (UsdcPool memory){
        return usdcPool;
    }

    function poolLength() public view returns (uint){
        return poolInfo.length;
    }

    function livepoolIndex() public view returns (uint[] memory, uint){
        uint[] memory index = new uint[](poolInfo.length);
        uint cnt;
        for (uint i = 0; i < poolInfo.length; i++) {
            if (poolInfo[i].endTime > block.timestamp) {
                index[cnt++] = i;
            }
        }
        return (index, cnt);
    }

    function pendingReward(uint _pid, address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        PoolInfo storage pool = poolInfo[_pid];
        UserPInfo storage userP = userPInfo[_pid][_user];
        uint256 _accUsdcPerShare = pool.accPerShare;
        if (block.timestamp <= pool.startTime) {
            return 0;
        }
        if (block.timestamp > pool.lastRewardTime && pool.amount != 0) {
            uint multiplier;
            if (block.timestamp > pool.endTime) {
                multiplier = pool.endTime.sub(pool.lastRewardTime);
            } else {
                multiplier = block.timestamp.sub(pool.lastRewardTime);
            }
            uint256 Reward = multiplier.mul(pool.tokenPerSec);
            _accUsdcPerShare = _accUsdcPerShare.add(Reward.mul(1e12).div(pool.amount));
        }
        return user.amount.mul(_accUsdcPerShare).div(1e12).sub(userP.rewardDebt).div(1e18);
    }

    function pendingrewards(address _user) public view returns (uint[] memory){
        uint[] memory pids = userInfo[_user].pids;
        uint[] memory rewards = new uint[](pids.length);
        for (uint i = 0; i < pids.length; i++) {
            rewards[i] = pendingReward(pids[i], _user);
        }
        return rewards;
    }

    function mytickets(address _user) public view returns (uint[] memory){
        uint[] memory my = new uint[](lotlist.length - lotstart);
        uint count;
        for (uint i = lotstart; i < lotlist.length; i++) {
            if (lotlist[i] == _user) {
                my[count++] = i;
            }
        }
        return my;
    }

    function totalticket() public view returns (uint){
        return lotlist.length - lotstart;
    }

    function pendingUsdc(address _user) public view returns (uint256){
        UserInfo storage user = userInfo[_user];
        uint256 _accUsdcPerShare = usdcPool.accUsdcPerShare;
        if (block.timestamp > usdcPool.lastRewardTime && totalAmount != 0) {
            uint256 multiplier = block.timestamp.sub(usdcPool.lastRewardTime);
            uint256 UsdcReward = multiplier.mul(usdcPool.usdcPerTime);
            _accUsdcPerShare = _accUsdcPerShare.add(UsdcReward.mul(1e12).div(totalAmount));
        }
        return user.amount.mul(_accUsdcPerShare).div(1e12).sub(user.rewardDebt).div(1e18);
    }

    /**Public functions */

    function updateUsdcPool() internal {
        if (block.timestamp <= usdcPool.lastRewardTime) {
            return;
        }
        if (totalAmount == 0) {
            usdcPool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp.sub(usdcPool.lastRewardTime);
        uint256 usdcReward = multiplier.mul(usdcPool.usdcPerTime);
        usdcPool.accUsdcPerShare = usdcPool.accUsdcPerShare.add(usdcReward.mul(1e12).div(totalAmount));
        usdcPool.lastRewardTime = block.timestamp;
    }

    function updatePool(uint _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.lastRewardTime >= pool.endTime || block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (totalAmount == 0 || pool.amount == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint multiplier;
        if (block.timestamp > pool.endTime) {
            multiplier = pool.endTime.sub(pool.lastRewardTime);
        } else {
            multiplier = block.timestamp.sub(pool.lastRewardTime);
        }
        uint256 Reward = multiplier.mul(pool.tokenPerSec);
        pool.accPerShare = pool.accPerShare.add(Reward.mul(1e12).div(pool.amount));

        pool.lastRewardTime = block.timestamp;
        if (block.timestamp > pool.endTime) {
            pool.lastRewardTime = pool.endTime;
        }
    }

    function deposit(uint256 _amount) public onlyApprovedContractOrEOA ispaused {
        UserInfo storage user = userInfo[msg.sender];
        updateUsdcPool();
        for (uint i = 0; i < user.pids.length; i++) {
            uint _pid = user.pids[i];
            if (skipPool[_pid]) {continue;}
            updatePool(_pid);
            uint pendingR = user.amount.mul(poolInfo[_pid].accPerShare).div(1e12).sub(userPInfo[_pid][msg.sender].rewardDebt);
            pendingR = pendingR.div(1e18);
            if (pendingR > 0) {
                poolInfo[_pid].token.safeTransfer(msg.sender, pendingR);
            }
        }
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(usdcPool.accUsdcPerShare).div(1e12).sub(user.rewardDebt);
            pending = pending.div(1e18);
            if (pending > 0) {
                safeUsdcTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint before = APOLLO.balanceOf(address(this));
            APOLLO.safeTransferFrom(address(msg.sender), address(this), _amount);
            APOLLO.safeTransfer(burnAddress, APOLLO.balanceOf(address(this)).sub(before));
            user.amount = user.amount.add(_amount);
            totalBurnt += _amount;
            totalAmount = totalAmount.add(_amount);
        }

        for (uint i = 0; i < user.pids.length; i++) {
            uint _pid = user.pids[i];
            if (skipPool[_pid]) {continue;}
            poolInfo[_pid].amount += _amount;
            userPInfo[_pid][msg.sender].rewardDebt = user.amount.mul(poolInfo[_pid].accPerShare).div(1e12);
        }
        user.rewardDebt = user.amount.mul(usdcPool.accUsdcPerShare).div(1e12);
        checkend();
    }

    function enroll(uint _pid) public onlyApprovedContractOrEOA {
        require(_pid < poolInfo.length && poolInfo[_pid].endTime > block.timestamp, "wrong pid");
        require(skipPool[_pid] == false);
        UserInfo storage user = userInfo[msg.sender];
        for (uint i = 0; i < user.pids.length; i++) {
            require(user.pids[i] != _pid, "duplicated pid");
        }
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        pool.amount += user.amount;
        user.pids.push(_pid);
        userPInfo[_pid][msg.sender].rewardDebt = user.amount.mul(poolInfo[_pid].accPerShare).div(1e12);
    }

    function compound() public onlyApprovedContractOrEOA returns (uint){
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0);
        updateUsdcPool();
        uint before = wmatic.balanceOf(address(this));
        for (uint i = 0; i < user.pids.length; i++) {
            uint _pid = user.pids[i];
            if (skipPool[_pid]) {continue;}
            updatePool(_pid);
            PoolInfo memory pool = poolInfo[_pid];
            uint pendingR = user.amount.mul(pool.accPerShare).div(1e12).sub(userPInfo[_pid][msg.sender].rewardDebt);
            pendingR = pendingR.div(1e18);
            if (pool.disableCompound) {
                if (pendingR > 0) {
                    pool.token.safeTransfer(msg.sender, pendingR);
                }
            } else {
                _safeSwap(pool.router, pendingR, address(pool.token), address(wmatic));
            }
        }

        uint beforeSing = APOLLO.balanceOf(address(this));
        //wmatic=>APOLLO
        _safeSwap(apollorouter, wmatic.balanceOf(address(this)).sub(before), address(wmatic), address(APOLLO));

        //USDC=>APOLLO
        uint256 pending = user.amount.mul(usdcPool.accUsdcPerShare).div(1e12).sub(user.rewardDebt);
        pending = pending.div(1e18);
        _safeSwap(apollorouter, pending, address(USDC), address(APOLLO));
        uint burningSing = APOLLO.balanceOf(address(this)).sub(beforeSing);
        user.amount += burningSing.mul(105).div(100);
        user.rewardDebt = user.amount.mul(usdcPool.accUsdcPerShare).div(1e12);
        for (uint i = 0; i < user.pids.length; i++) {
            uint _pid = user.pids[i];
            if (skipPool[_pid]) {continue;}
            poolInfo[_pid].amount += burningSing.mul(105).div(100);
            userPInfo[_pid][msg.sender].rewardDebt = user.amount.mul(poolInfo[_pid].accPerShare).div(1e12);
        }
        APOLLO.transfer(burnAddress, burningSing);
        totalBurnt += burningSing;
        totalAmount += burningSing.mul(105).div(100);

        if (burningSing > entryMin) {//enroll for lottery
            lotlist.push(msg.sender);
        }
        checkend();
        return burningSing;
    }


    function addRepo(uint _amount) public {
        require(msg.sender == address(APOLLO) || msg.sender == owner());
        uint _lotadd = _amount.mul(lotrate).div(10000);
        lotsize = lotsize.add(_lotadd);
        newRepo = newRepo.add(_amount.sub(_lotadd));
    }

    /**Internal functions */

    function checkend() internal {//already updated pool above.
        deletepids();
        if (endtime <= block.timestamp) {
            endtime = block.timestamp.add(period);
            if (newRepo > 10 ** 7) {//USDC decimal 6 in polygon. should change on other chains.
                safeUsdcTransfer(msg.sender, 10 ** 7);
                //reward for the first resetter
                newRepo = newRepo.sub(10 ** 7);
            }
            winner = address(msg.sender);
            currentRepo = newRepo.mul(999).div(1000);
            //in case of error by over-paying
            newRepo = 0;
            if (usdcPool.idx == 3) {
                usdcPool.usdcPerTime -= usdcPool.wkUnit[0];
                usdcPool.idx = 0;
                usdcPool.wkUnit[0] = currentRepo.mul(1e18).div(period * 4);
                usdcPool.usdcPerTime += usdcPool.wkUnit[0];
            } else {
                uint idx = usdcPool.idx;
                usdcPool.usdcPerTime = usdcPool.usdcPerTime.sub(usdcPool.wkUnit[idx + 1]);
                usdcPool.idx++;
                usdcPool.wkUnit[usdcPool.idx] = currentRepo.mul(1e18).div(period * 4);
                usdcPool.usdcPerTime += usdcPool.wkUnit[usdcPool.idx];
            }
            pickwin();
        }
    }

    function deletepids() internal {
        UserInfo storage user = userInfo[msg.sender];
        for (uint i = 0; i < user.pids.length; i++) {
            if (poolInfo[user.pids[i]].endTime <= block.timestamp) {
                user.pids[i] = user.pids[user.pids.length - 1];
                user.pids.pop();
                deletepids();
                break;
            }
        }
    }

    function pickwin() internal {
        uint _mod = lotlist.length - lotstart;
        bytes32 _structHash;
        uint256 _randomNumber;
        _structHash = keccak256(
            abi.encode(
                msg.sender,
                block.difficulty,
                gasleft()
            )
        );
        _randomNumber = uint256(_structHash);
        assembly {_randomNumber := mod(_randomNumber, _mod)}
        winnum = lotstart + _randomNumber;
        lotwinner = lotlist[winnum];
        safeUsdcTransfer(lotwinner, lotsize);
        lotsize = 0;
        lotstart += _mod;
    }

    function _safeSwap(
        address _router,
        uint256 _amountIn,
        address token0, address token1
    ) internal {
        if (_amountIn > 0) {
            address[] memory _path = new address[](2);
            uint bal = IERC20(token0).balanceOf(address(this));
            if (_amountIn < bal) {
                bal = _amountIn;
            }
            _path[0] = token0;
            _path[1] = token1;
            IUniswapV2Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                bal,
                0,
                _path,
                address(this),
                now.add(600)
            );
        }
    }

    function safeUsdcTransfer(address _to, uint256 _amount) internal {
        uint256 balance = USDC.balanceOf(address(this));
        if (_amount > balance) {
            USDC.safeTransfer(_to, balance);
            totalpayout = totalpayout.add(balance);
        } else {
            USDC.safeTransfer(_to, _amount);
            totalpayout = totalpayout.add(_amount);
        }
    }

    /*governance functions*/

    function addpool(uint _amount, uint _startTime, uint _endTime, IERC20 _token, address _router) public onlyOwner {
        require(_startTime > block.timestamp && _endTime > _startTime, "wrong time");
        poolInfo.push(PoolInfo({
        initamt : _amount,
        amount : 0,
        startTime : _startTime,
        endTime : _endTime,
        tokenPerSec : _amount.mul(1e18).div(_endTime - _startTime), //X10^18
        accPerShare : 0,
        token : _token,
        lastRewardTime : _startTime,
        router : _router,
        disableCompound : false//in case of error
        }));
        _token.approve(_router, uint(- 1));
    }

    function start(uint _period) public onlyOwner {
        paused = false;
        period = _period;
        endtime = block.timestamp.add(period);
        currentRepo = newRepo;
        usdcPool.usdcPerTime = currentRepo.mul(1e18).div(period * 4);
        usdcPool.wkUnit[0] = usdcPool.usdcPerTime;
        newRepo = 0;
    }

    function stopPool(uint _pid) public onlyOwner {
        skipPool[_pid] = !skipPool[_pid];
        //toggle
    }

    function pause(bool _paused) public onlyOwner {
        paused = _paused;
    }

    function setPeriod(uint _period) public onlyOwner {
        period = _period;
    }

    function setMin(uint _entryMin) public onlyOwner {
        entryMin = _entryMin;
    }

    function disableCompound(uint _pid, bool _disable) public onlyOwner {
        poolInfo[_pid].disableCompound = _disable;
    }

    function setApprovedContract(address _contract, bool _status)
    external
    onlyOwner
    {
        approvedContracts[_contract] = _status;
    }

}
