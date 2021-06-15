//Socials




// SPDX-License-Identifier: MIT





pragma solidity ^0.8.0;


import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './interfaces/SafeBEP20.sol';
import './Electron.sol';


// MasterAtom is the master of Electron. He can make Electron and he is a fair Atom.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Electron is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterAtom is Ownable, ReentrancyGuard {
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Electrons
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accElectronPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accElectronPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. Electrons to distribute per block.
        uint256 lastRewardBlock;    // Last block number that Electrons distribution occurs.
        uint256 accElectronPerShare; // Accumulated Electrons per share, times 1e12. See below.
        uint16 depositFeeBP;        // Deposit fee in basis points
    }

    struct FeeInfo{
        address feeAddress;
        uint16 feeAddressShare; //(0-100)  in Basis points. the sum of all in array must sum 100.
    }
    FeeInfo[] public feeArray;

    // The Electron TOKEN!
    Electron public _electron;
    // Dev address.
    address public _devAddress;
    // Deposit/Withdraw Fee address
    address public _feeAddress;
    // Electron tokens created per block.
    uint256 public _electronPerBlock;

    
    

    // Info of each pool.
    PoolInfo[] public _poolInfo;
    // Exist a pool with that token?
    mapping(IBEP20 => bool) public _poolExistence;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public _userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public _totalAllocPoint;
    // The block number when Electron mining starts.
    uint256 public _startBlock;

    modifier nonDuplicated(IBEP20 lpToken_) {
        require(!_poolExistence[lpToken_], 'MasterAtom: nonDuplicated: duplicated token');
        _;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 ElectronPerBlock);

    constructor(
        Electron electron_,
        address devAddress_,
        address feeAddress_
        //uint256 electronPerBlock_
        //uint256 startBlock_
    ) {
        _electron = electron_;
        _devAddress = devAddress_;
        _feeAddress = feeAddress_;
        feeArray.push(
            FeeInfo({  
                feeAddress:feeAddress_,
                feeAddressShare:100
        }));
        //_electronPerBlock = electronPerBlock_;
        _electronPerBlock = ((5 * (10**_electron.decimals())) / 100); // 0.05 electrons per block
        //_startBlock = startBlock_;
        _startBlock = block.number + 43200; // start block 1 days after deploy, initial date.. might change
    }

    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }

    
    

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 allocPoint_, IBEP20 lpToken_, uint16 depositFeeBP_, bool withUpdate_) public onlyOwner nonDuplicated(lpToken_) {
        require(depositFeeBP_ <= 400, 'MasterAtom: Add: Invalid deposit fee basis points, must be [0-400]'); //deposit Fee capped at 400 -> 4%
        if (withUpdate_) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        _totalAllocPoint += allocPoint_;
        _poolExistence[lpToken_] = true;
        _poolInfo.push(
            PoolInfo({
                lpToken : lpToken_,
                allocPoint : allocPoint_,
                lastRewardBlock : lastRewardBlock,
                accElectronPerShare : 0,
                depositFeeBP : depositFeeBP_
        }));
    }

    // Update the given pool's Electron allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 pid_, uint256 allocPoint_, uint16 depositFeeBP_, bool withUpdate_) public onlyOwner {
        require(depositFeeBP_ <= 400, 'MasterAtom: Set: Invalid deposit fee basis points, must be [0-400]'); //deposit Fee capped at 400 -> 4%
        if (withUpdate_) {
            massUpdatePools();
        }
        _totalAllocPoint = ((_totalAllocPoint + allocPoint_)- _poolInfo[pid_].allocPoint);
        _poolInfo[pid_].allocPoint = allocPoint_;
        _poolInfo[pid_].depositFeeBP = depositFeeBP_;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 from_, uint256 to_) public pure returns (uint256) {
        return to_-from_;
    }

    // View function to see pending Electrons on frontend.
    function pendingElectron(uint256 pid_, address user_) external view returns (uint256) {
        PoolInfo storage pool = _poolInfo[pid_];
        UserInfo storage user = _userInfo[pid_][user_];
        uint256 accElectronPerShare = pool.accElectronPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 electronReward = ((multiplier*_electronPerBlock*pool.allocPoint)/_totalAllocPoint);
            accElectronPerShare += ((electronReward* 1e12)/lpSupply);
        }
        return (((user.amount*accElectronPerShare)/ 1e12) - user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        for (uint256 pid = 0; pid < _poolInfo.length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 pid_) public {
        PoolInfo storage pool = _poolInfo[pid_];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 electronReward = ((multiplier*_electronPerBlock*pool.allocPoint)/_totalAllocPoint);
        _electron.mint(_devAddress, electronReward/10);
        _electron.mint(address(this), electronReward);
        pool.accElectronPerShare += ((electronReward*1e12)/lpSupply);
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterAtom for Electron allocation.
    function deposit(uint256 pid_, uint256 amount_) public nonReentrant {
        PoolInfo storage pool = _poolInfo[pid_];
        UserInfo storage user = _userInfo[pid_][_msgSender()];
        updatePool(pid_);
        if (user.amount > 0) {
            uint256 pending = (((user.amount*pool.accElectronPerShare)/1e12) - user.rewardDebt);
            if (pending > 0) {
                safeElectronTransfer(_msgSender(), pending);
            }
        }
        if (amount_ > 0) {
            pool.lpToken.safeTransferFrom(_msgSender(), address(this), amount_);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = ((amount_*pool.depositFeeBP)/10000);
                distributeFee(pool.lpToken, depositFee);
                //pool.lpToken.safeTransfer(_feeAddress, depositFee);
                user.amount = (user.amount + amount_) - depositFee;
            } else {
                user.amount += amount_;
            }
        }
        user.rewardDebt = ((user.amount*pool.accElectronPerShare)/1e12);
        emit Deposit(_msgSender(), pid_, amount_);
    }


    function distributeFee(IBEP20 lpToken, uint256 amount_) internal {
        uint256 acumulated;
        for (uint256 i = 1; i<feeArray.length;++i){
            uint256 fraction = ((amount_*feeArray[i].feeAddressShare)/100);
            lpToken.safeTransfer(feeArray[i].feeAddress, fraction);
            acumulated+=fraction;
        }
        lpToken.safeTransfer(feeArray[0].feeAddress, amount_-acumulated);
    }

    function setFeeAddressArray(FeeInfo[] calldata fiarray_) public{
        require(_msgSender() == _feeAddress, 'MasterAtom: setFeeAddressArray: Only feeAddress can set');
        uint16 count;
        delete feeArray;
        for (uint256 i = 0; i<fiarray_.length;++i){
            count+= fiarray_[i].feeAddressShare;
            feeArray.push(FeeInfo({
                feeAddress:fiarray_[i].feeAddress,
                feeAddressShare:fiarray_[i].feeAddressShare
            }));
        }
        require(count==100,'MasterAtom: setFeeAddressArray: sum of shares must be 100');
        //feeArray = fiarray_;
    }



    // Withdraw LP tokens from MasterAtom.
    function withdraw(uint256 pid_, uint256 amount_) public nonReentrant {
        PoolInfo storage pool = _poolInfo[pid_];
        UserInfo storage user = _userInfo[pid_][_msgSender()];
        require(user.amount >= amount_, 'MasterAtom: Withdraw: not enough to withdraw');
        updatePool(pid_);
        uint256 pending = (((user.amount*pool.accElectronPerShare)/1e12) - user.rewardDebt);
        if (pending > 0) {
            safeElectronTransfer(_msgSender(), pending);
        }
        if (amount_ > 0) {
            user.amount -= amount_;
            pool.lpToken.safeTransfer(_msgSender(), amount_);
        }
        user.rewardDebt = ((user.amount*pool.accElectronPerShare)/1e12);
        emit Withdraw(_msgSender(), pid_, amount_);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 pid_) public nonReentrant {
        PoolInfo storage pool = _poolInfo[pid_];
        UserInfo storage user = _userInfo[pid_][_msgSender()];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(_msgSender(), amount);
        emit EmergencyWithdraw(_msgSender(), pid_, amount);
    }

    // Safe Electron transfer function, just in case if rounding error causes pool to not have enough Electrons.
    function safeElectronTransfer(address to_, uint256 amount_) internal {
        uint256 electronBal = _electron.balanceOf(address(this));
        bool transferSuccess = amount_ > electronBal? _electron.transfer(to_, electronBal): _electron.transfer(to_, amount_);
        require(transferSuccess, 'MasterAtom: safeElectronTransfer: transfer failed');
    }

    // Update dev address by the previous dev.
    function setDevAddress(address devAddress_) public {
        require(_msgSender() == _devAddress, 'MasterAtom: setDevAddress: Only dev can set');
        _devAddress = devAddress_;
        emit SetDevAddress(_msgSender(), devAddress_);
    }

    function setFeeAddress(address feeAddress_) public {
        require(_msgSender() == _feeAddress, 'MasterAtom: setFeeAddress: Only feeAddress can set');
        _feeAddress = feeAddress_;
        emit SetFeeAddress(_msgSender(), feeAddress_);
    }

    // Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 electronPerBlock_) public onlyOwner {
        require (electronPerBlock_<=10**_electron.decimals(),'MasterAtom: updateEmissionRate: Max emission 1 electron per block');
        massUpdatePools();
        _electronPerBlock = electronPerBlock_;
        emit UpdateEmissionRate(_msgSender(), electronPerBlock_);
    }

    // Only update before start of farm
    function updateStartBlock(uint256 startBlock_) public onlyOwner {
	    require(startBlock_ > block.number, 'MasterAtom: updateStartBlock: No timetravel allowed!');
        _startBlock = startBlock_;
    }

    // Retrieve to the fee address any token that could have been sent to electron contract by mistake. recieved on fee address it will be used for dividends. 
    function retrieveErrorTokensOnElectronAddress(IBEP20 token_) public onlyOwner{
        _electron.retrieveErrorTokens(token_, _feeAddress);
    }

    function setMaxTxPercentage(uint16 newPercentage)public onlyOwner{
        _electron.setMaxTxPercentage(newPercentage);
    }

    function setExcludeMaxTransactionAddress(address exclude, bool state) public onlyOwner{
        _electron.setExcludeMaxTransactionAddress(exclude, state);
    }

}