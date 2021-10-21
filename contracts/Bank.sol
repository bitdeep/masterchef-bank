// SPDX-License-Identifier: UNLICENSED
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

contract Bank2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
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
        IBEP20 token;
        uint lastRewardTime;
        address router;
        bool disableCompound;//in case of error
    }

    struct UserPInfo {
        uint rewardDebt;
    }

    struct IronPool {
        //usdcPerSec everyweek
        uint idx;
        uint[] wkUnit; //weekly usdcPerSec. 4week cycle
        uint usdcPerTime;//*1e18
        uint startTime;
        uint accIronPerShare;
        uint lastRewardTime;
    }

    /**Variables */

    mapping(address => UserInfo) public userInfo;
    PoolInfo[] public poolInfo;
    mapping(uint => bool) public skipPool;//in case of stuck in one token.
    mapping(uint => mapping(address => UserPInfo)) public userPInfo;
    address[] public lotlist;
    uint public lotstart = 1;
    IronPool public usdcPool;
    IBEP20 public APOLLO = IBEP20(0x87cf37B07a5f879c1af35532862e6229E90C72AF);
    IBEP20 public IRON = IBEP20(0xD86b5923F3AD7b585eD81B448170ae026c65ae9a); // IRON
    IBEP20 public wbnb = IBEP20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270); // WMATIC
    address public dfynRouter = 0xA102072A4C07F06EC3B4900FDC4C7B80b6c57429;  // DFYN RT
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

    // use for testing only

    constructor(address _lp, address _busd, address _wbnb, address _router) public {
        APOLLO = IBEP20(_lp);
        dfynRouter = _router;
        IRON = IBEP20(_busd);
        wbnb = IBEP20(_wbnb);
        paused = false;
        usdcPool.wkUnit = [0, 0, 0, 0];
        devaddr = address(msg.sender);
        wbnb.approve(dfynRouter, uint(- 1));
        IRON.approve(dfynRouter, uint(- 1));
        lotlist.push(burnAddress);
    }


    // mainnet
    /*
    constructor() public {
        paused = false;
        usdcPool.wkUnit = [0, 0, 0, 0];
        devaddr = address(0x7cef2432A2690168Fb8eb7118A74d5f8EfF9Ef55);
        wbnb.approve(dfynRouter, uint(- 1));
        IRON.approve(dfynRouter, uint(- 1));
        lotlist.push(burnAddress);
    }
*/
    modifier ispaused(){
        require(paused == false, "paused");
        _;
    }

    /**View functions  */
    function userinfo(address _user) public view returns (UserInfo memory){
        return userInfo[_user];
    }

    function usdcinfo() public view returns (IronPool memory){
        return usdcPool;
    }

    function poolLength() public view returns (uint){
        return poolInfo.length;
    }

    function getTime() public view returns (uint256){
        return block.timestamp;
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
        uint256 _accIronPerShare = pool.accPerShare;
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
            _accIronPerShare = _accIronPerShare.add(Reward.mul(1e12).div(pool.amount));
        }
        return user.amount.mul(_accIronPerShare).div(1e12).sub(userP.rewardDebt).div(1e18);
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

    function pendingIRON(address _user) public view returns (uint256){
        UserInfo storage user = userInfo[_user];
        uint256 _accIronPerShare = usdcPool.accIronPerShare;
        if (block.timestamp > usdcPool.lastRewardTime && totalAmount != 0) {
            uint256 multiplier = block.timestamp.sub(usdcPool.lastRewardTime);
            uint256 IronReward = multiplier.mul(usdcPool.usdcPerTime);
            _accIronPerShare = _accIronPerShare.add(IronReward.mul(1e12).div(totalAmount));
        }
        return user.amount.mul(_accIronPerShare).div(1e12).sub(user.rewardDebt).div(1e18);
    }

    /**Public functions */

    function updateIronPool() internal {
        if (block.timestamp <= usdcPool.lastRewardTime) {
            return;
        }
        if (totalAmount == 0) {
            usdcPool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp.sub(usdcPool.lastRewardTime);
        uint256 usdcReward = multiplier.mul(usdcPool.usdcPerTime);
        usdcPool.accIronPerShare = usdcPool.accIronPerShare.add(usdcReward.mul(1e12).div(totalAmount));
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
        updateIronPool();
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
            uint256 pending = user.amount.mul(usdcPool.accIronPerShare).div(1e12).sub(user.rewardDebt);
            pending = pending.div(1e18);
            if (pending > 0) {
                safeIronTransfer(msg.sender, pending);
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
        user.rewardDebt = user.amount.mul(usdcPool.accIronPerShare).div(1e12);
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
        updateIronPool();
        uint before = wbnb.balanceOf(address(this));
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
                _safeSwap(pool.router, pendingR, address(pool.token), address(wbnb));
            }
        }

        uint beforeSing = APOLLO.balanceOf(address(this));
        //wbnb=>APOLLO
        _safeSwap(dfynRouter, wbnb.balanceOf(address(this)).sub(before), address(wbnb), address(APOLLO));

        //IRON=>APOLLO
        uint256 pending = user.amount.mul(usdcPool.accIronPerShare).div(1e12).sub(user.rewardDebt);
        pending = pending.div(1e18);
        _safeSwap(dfynRouter, pending, address(IRON), address(APOLLO));
        uint burningSing = APOLLO.balanceOf(address(this)).sub(beforeSing);
        user.amount += burningSing.mul(105).div(100);
        user.rewardDebt = user.amount.mul(usdcPool.accIronPerShare).div(1e12);
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


    function addManualRepo(uint _amount) public {
        IRON.safeTransferFrom(msg.sender, address(this), _amount);
        addRepo(_amount);
    }
    function addRepo(uint _amount) public {
        require(msg.sender == address(APOLLO) || msg.sender == owner() || msg.sender == devaddr, "not authorized to repo");
        uint _lotadd = _amount.mul(lotrate).div(10000);
        lotsize = lotsize.add(_lotadd);
        newRepo = newRepo.add(_amount.sub(_lotadd));
    }

    /**Internal functions */

    function checkend() internal {//already updated pool above.
        deletepids();
        if (endtime <= block.timestamp) {
            endtime = block.timestamp.add(period);
            if (newRepo > 10 ** 19) {//BUSD decimal 18 in bsc. should change on other chains.
                safeIronTransfer(msg.sender, 10 ** 19);
                //reward for the first resetter
                newRepo = newRepo.sub(10 ** 19);
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
        safeIronTransfer(lotwinner, lotsize);
        lotsize = 0;
        lotstart += _mod;
    }

    function _safeSwap(
        address _router,
        uint256 _amountIn,
        address token0, address token1
    ) internal {
        uint bal = IBEP20(token0).balanceOf(address(this));
        if (_amountIn < bal) {
            bal = _amountIn;
        }
        if (bal > 0) {
            address[] memory _path = new address[](2);
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

    function safeIronTransfer(address _to, uint256 _amount) internal {
        uint256 balance = IRON.balanceOf(address(this));
        if (_amount > balance) {
            IRON.safeTransfer(_to, balance);
            totalpayout = totalpayout.add(balance);
        } else {
            IRON.safeTransfer(_to, _amount);
            totalpayout = totalpayout.add(_amount);
        }
    }

    /*governance functions*/

    function addpool(uint _amount, uint _startTime, uint _endTime, IBEP20 _token, address _router) public onlyOwner {
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
