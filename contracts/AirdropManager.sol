//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './tools/AccessControl.sol';

contract AdminPanel is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public feeInWei;
    uint256 public instanceIDs;
    AirManInstance[] public deployedManagersById;

    struct AirManInstance {
        string[] CID;
        uint256 id;
        address instanceOwner;
        address instanceAddress;
        address instanceToken;
    }

    mapping (address =>  AirManInstance[]) public deployedByUser;

    event NewAirdropManagerDeployed(address payable managerOwner, address tokenAddress, address deployedManager);
    event NewFee(uint256 newFee);
    event EtherWithdrawed(uint256 amount);

    constructor(uint256 _feeInWei) {
        _grantRole(ADMIN_ROLE, msg.sender);

        feeInWei = _feeInWei;
        instanceIDs = 0;
    }

    receive() external payable{
        require(false, "AdminPanel does not accept direct payments");
    }

    fallback() external payable{
        require(false, "AdminPanel does not accept direct payments");
    }

    function deployFreeAirdropManagerInstance(
        string[] memory cid,
        address payable _newOwner,
        address _instanceToken,
        uint256 _initialBalance
        ) external onlyRole(ADMIN_ROLE) {
        _deployNewAirMan(cid, _instanceToken, _initialBalance, _newOwner);
    }

    // This fee could either be 0 or any other value
    function setFeeInWei(uint256 newFeeInWei) external onlyRole(ADMIN_ROLE) {
        require(newFeeInWei != feeInWei, 'New fee needs to be different from existing fee');
        feeInWei = newFeeInWei;

        emit NewFee(newFeeInWei);
    }

    // For frontend purposes
    function getDeployedInstancesByOwner(address instanceOwner) public view returns (uint256[] memory) {
        uint256[] memory instances = new uint256[](deployedByUser[instanceOwner].length);

        for (uint256 i = 0; i < deployedByUser[instanceOwner].length; i++) {
            instances[i] = deployedByUser[instanceOwner][i].id;
        }

        return instances;
    }

    function newAirdropManagerInstance(string[] memory cid, address _instanceToken, uint256 _initialBalance) public payable {
        require(msg.value == feeInWei,  'Exact fee not sent');

        _deployNewAirMan(cid, _instanceToken, _initialBalance, payable(msg.sender));
    }

    function _deployNewAirMan(string[] memory cid, address _instanceToken, uint256 _initialBalance, address payable _newOwner) internal {
        require(ERC20(_instanceToken).balanceOf(_newOwner) >= _initialBalance);
        require(ERC20(_instanceToken).allowance(_newOwner, address(this)) >= _initialBalance,
            'No allowance to send to the new AirMan'
        );
        AirdropManager newInstance = new AirdropManager(cid, _newOwner, _instanceToken);
        require(ERC20(_instanceToken).transferFrom(_newOwner, address(newInstance), _initialBalance));

        AirManInstance memory instance;
        instance.CID = cid;
        instance.id = instanceIDs;
        instance.instanceOwner = _newOwner;
        instance.instanceAddress = address(newInstance);
        instance.instanceToken = _instanceToken;

        deployedManagersById.push(instance);
        deployedByUser[_newOwner].push(instance);

        instanceIDs++;

        emit NewAirdropManagerDeployed(payable(msg.sender), _instanceToken, address(newInstance));
    }

    function withdrawEther() external onlyRole(ADMIN_ROLE) {
        require(address(this).balance > 0, 'No ether to withdraw');
        uint256 amountToSend = address(this).balance;
        payable(msg.sender).transfer(amountToSend);

        emit EtherWithdrawed(amountToSend);
    }

}


contract AirdropManager {
    string[] public CID;
    address payable public owner;
    address public tokenAddress;
    uint256 internal lastCampaignID;
    Campaign[] public campaigns;
    // TO DO add a function to track the airdrops a user has been part of

    struct Campaign {
        uint256 campaignID;
        uint256 endDate;
        uint256 amountToAirdrop;
        uint256 fee;
        uint256 amountForEachUser; // can be 0
        bool fixedAmount;
        bool isPrivate;
        AirdropCampaign campaignAddress;
    }

    event NewAirdropCampaign(uint256 endsIn, uint256 amountToAirdrop, address instanceAddress);
    event EtherReceived(uint256 amount, address sender);
    event EtherWithdrawed(uint256 amount);
    event WithdrawedTokens(uint256 Amount);

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(string[] memory cid, address payable ownerAddress, address _tokenAddress) {
        require(ownerAddress != address(0));
        require(_tokenAddress != address(0));

        CID = cid;
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
        lastCampaignID = 0;
    }

    receive() external payable{
        emit EtherReceived(msg.value, msg.sender);
    }

    function newAirdropCampaign(
        uint256 endsIn, // In seconds
        uint256 amountForCampaign,
        uint256 whitelistFee, // In wei
        uint256 amountForEachUser,
        uint256 maxUserAmount,
        bool hasFixedAmount,
        bool _isPrivate
    )
        public
        onlyOwner
        returns (AirdropCampaign)
    {
        require(amountForCampaign <= ERC20(tokenAddress).balanceOf(address(this)),
            'Not enough tokens for the new Campaign');
        require(endsIn > 0);
        if (hasFixedAmount)
            require(maxUserAmount * amountForEachUser == amountForCampaign, 'Wrong amount for each user');

        AirdropCampaign newInstance =
            new AirdropCampaign(
                block.timestamp + endsIn,
                whitelistFee,
                amountForCampaign,
                maxUserAmount,
                amountForEachUser,
                owner,
                tokenAddress,
                payable(address(this)),
                hasFixedAmount,
                _isPrivate
            );

        require(ERC20(tokenAddress).transfer(address(newInstance), amountForCampaign));

        campaigns.push(
            Campaign({
                campaignID: lastCampaignID,
                endDate: block.timestamp + endsIn,
                amountToAirdrop: amountForCampaign,
                fee: whitelistFee,
                amountForEachUser: amountForEachUser,
                fixedAmount: hasFixedAmount,
                isPrivate: _isPrivate,
                campaignAddress: newInstance
            })
        );

        lastCampaignID++;

        emit NewAirdropCampaign(endsIn, amountForCampaign, address(newInstance));

        return newInstance;
    }

    // For frontend purposes
    function showDeployedCampaigns() external view returns (uint256) {
        return campaigns.length;
    }

    /// @param option: Can be 0 for ether or 1 for tokens
    function manageFunds(uint8 option) external onlyOwner {
        if (option == 0) { // Withdraw Ether
            require(address(this).balance > 0, 'No ether to withdraw');
            uint256 amountToSend = address(this).balance;
            owner.transfer(amountToSend);

            emit EtherWithdrawed(amountToSend);
        } else if (option == 1) { // Withdraw Tokens
            uint256 toSend = ERC20(tokenAddress).balanceOf(address(this));
            require(ERC20(tokenAddress).transfer(owner, toSend));

            emit WithdrawedTokens(toSend);
        } else {
            revert('Only accepts 0 or 1');
        }
    }

    function editCID(string[] memory newCID) external onlyOwner {
        CID = newCID;
    }

}

// to do refactor onlyOwner
contract AirdropCampaign {
    uint256 public tokenAmount = 0;
    uint256 public claimableSince;
    uint256 public maxParticipantAmount; // helps when fixedAmount is true
    uint256 public participantAmount = 0;
    uint256 public unclaimedAirdrops = 0;
    uint256 public whitelistFee;
    uint256 public amountForEachUser;
    uint256 public ownerTokenWithdrawDate; // The date the owner can withdraw the tokens
    address payable owner;
    address payable public airMan;
    address public tokenAddress;
    bool public fixedAmount;
    bool public isPrivate;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    struct Participant {
        address ParticipantAddress;
        bool isBanned;
        bool claimed;
    }

    mapping(address => Participant) public participantInfo;

    event NewParticipant(address newParticipant);
    event EtherWithdrawed(uint256 amount);
    event TokenClaimed(address participantAddress, uint256 claimed);
    event UserParticipationToggled(address participantAddress, bool isBanned);
    event WithdrawedTokens(uint256 Amount);
    event ModifiedValue(uint256 newValue);

    constructor(
        uint256 endDate,
        uint256 _whitelistFee,
        uint256 amountForCampaign,
        uint256 _maxParticipantAmount,
        uint256 valueForEachUser,  // can be 0
        address payable ownerAddress,
        address _tokenAddress,
        address payable airManAddress,
        bool hasFixedAmount,
        bool _isPrivate
    )
    {
        require(ownerAddress != address(0));
        require(_tokenAddress != address(0));

        claimableSince = endDate;
        ownerTokenWithdrawDate = claimableSince + (claimableSince - block.timestamp);
        whitelistFee = _whitelistFee;
        tokenAmount = amountForCampaign;
        maxParticipantAmount = _maxParticipantAmount;
        amountForEachUser = valueForEachUser;
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
        airMan = airManAddress;
        fixedAmount = hasFixedAmount;
        isPrivate = _isPrivate;
    }

    receive() external payable{
        require(msg.value == whitelistFee,
        'Must send the exact whitelistFee value');
        addToPayableWhitelist();
    }

    fallback() external payable{
        revert();
    }

    // Admin functions
    function batchAddToWhitelist(address[] memory PartAddr) external onlyOwner{
        for (uint256 id = 0; id < PartAddr.length; ++id) {
            _addToWhitelist(PartAddr[id]);
        }
    }

    function updateFee(uint256 newValue) external onlyOwner {
        require(newValue != whitelistFee, "The new fee can't be the same as the old one");
        whitelistFee = newValue;

        emit ModifiedValue(newValue);
    }

    function toggleParticipation(address PartAddr) external onlyOwner {
        require(block.timestamp <= claimableSince, "Can't modify users, time is up");

        if (participantInfo[PartAddr].ParticipantAddress != PartAddr) {
            participantInfo[PartAddr].ParticipantAddress = PartAddr;
        }
        participantInfo[PartAddr].isBanned = !(participantInfo[PartAddr].isBanned);

        emit UserParticipationToggled(PartAddr, participantInfo[PartAddr].isBanned);
    }

    function toggleIsPrivate() external onlyOwner {
        require(block.timestamp <= claimableSince, "Can't modify state, time is up");
        isPrivate = !isPrivate;
    }

    function manageFunds() external onlyOwner {
        require(block.timestamp >= ownerTokenWithdrawDate,
            'Tokens not claimable yet');
        uint256 toSend = ERC20(tokenAddress).balanceOf(address(this));
        require(ERC20(tokenAddress).transfer(airMan, toSend));
        if (address(this).balance > 0) {
            require(owner.send(address(this).balance));
        }

        emit WithdrawedTokens(toSend);
    }

    // User functions
    function addToPayableWhitelist() public payable { // This is payable but if fee is 0 then its free
        require (!isPrivate, 'Airdrop is private');
        require(msg.value == whitelistFee,
            'Exact fee not sent');
        _addToWhitelist(msg.sender);
    }

    function receiveTokens() external {
        require(block.timestamp >= claimableSince, 'Airdrop not claimable yet');
        require(participantInfo[msg.sender].isBanned == false, "You can't claim this airdrop");
        require(participantInfo[msg.sender].claimed == false, 'You already claimed');

        uint256 _ToSend;
        if (fixedAmount) {
            _ToSend = amountForEachUser;
        } else {
            _ToSend = tokenAmount / participantAmount;
        }

        participantInfo[msg.sender].claimed = true;
        require(ERC20(tokenAddress).transfer(msg.sender, _ToSend));
        unclaimedAirdrops--;

        emit TokenClaimed(msg.sender, _ToSend);
    }

    function retireFromCampaign() public {
        require(participantInfo[msg.sender].ParticipantAddress == msg.sender, 'You are not participating');
        require(block.timestamp <= claimableSince, 'Campaign over, can not retire');

        // user information is no longer tracked
        participantInfo[msg.sender].ParticipantAddress = address(0);
        unclaimedAirdrops--;
        participantAmount--;

        payable(msg.sender).transfer(whitelistFee);
    }

    function _addToWhitelist(address PartAddr) internal { // ** related
        require(PartAddr != address(0));
        require(block.timestamp <= claimableSince,
            'Campaign ended');
        require(participantInfo[PartAddr].ParticipantAddress != PartAddr,
            string(abi.encodePacked("Participant already exists ", PartAddr)));
        if (fixedAmount) {
            require(participantAmount + 1 <= maxParticipantAmount,
            "Can't join, whitelist is full");
        }
        participantInfo[PartAddr].ParticipantAddress = PartAddr;
        participantInfo[PartAddr].claimed = false;

        participantAmount++;
        unclaimedAirdrops++;

        emit NewParticipant(PartAddr);
    }

}

interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}