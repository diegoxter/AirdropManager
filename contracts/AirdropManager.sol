//SPDX-License-Identifier:UNLICENSE
pragma solidity ^0.8.16;

contract AdminPanel {
    address payable public owner = payable(address(0));
    uint256 public feeInWei;
    uint256 public instanceIDs;

    struct AirManInstance {
        uint256 id;
        address instanceOwner;
        address instanceAddress;
        address instanceToken;
    }

    mapping (address =>  AirManInstance[]) public deployedByUser;

    event NewAirdropManagerDeployed(address payable managerOwner, address tokenAddress, address deployedManager);
    event NewFee(uint256 newFee);
    event EtherWithdrawed(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(uint256 _feeInWei) {
        owner = payable(msg.sender);
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
        address payable _newOwner,
        address _instanceToken,
        uint256 _initialBalance
        ) external onlyOwner {
        _deployNewAirMan(_instanceToken, _initialBalance, _newOwner);
    }

    // This fee could either be 0 or any other value
    function setFeeInWei(uint256 newFeeInWei) external onlyOwner {
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

    function newAirdropManagerInstance(address _instanceToken, uint256 _initialBalance) public payable
    {
        require(msg.value == feeInWei,
            'Exact fee not sent');

        _deployNewAirMan(_instanceToken, _initialBalance, payable(msg.sender));
    }

    function _deployNewAirMan(address _instanceToken, uint256 _initialBalance, address payable _newOwner) internal {
        require(ERC20(_instanceToken).balanceOf(_newOwner) >= _initialBalance);
        require(ERC20(_instanceToken).allowance(_newOwner, address(this)) >= _initialBalance,
            'No allowance to send to the new AirMan'
        );
        AirdropManager newInstance = new AirdropManager(_newOwner, _instanceToken);
        require(ERC20(_instanceToken).transferFrom(_newOwner, address(newInstance), _initialBalance));

        AirManInstance memory instance;
        instance.id = instanceIDs;
        instance.instanceOwner = _newOwner;
        instance.instanceAddress = address(newInstance);
        instance.instanceToken = _instanceToken;

        deployedByUser[_newOwner].push(instance);

        instanceIDs++;

        emit NewAirdropManagerDeployed(payable(msg.sender), _instanceToken, address(newInstance));
    }

    function withdrawEther() external onlyOwner {
        require(address(this).balance > 0, 'No ether to withdraw');
        uint256 amountToSend = address(this).balance;
        owner.transfer(amountToSend);

        emit EtherWithdrawed(amountToSend);
    }
}


contract AirdropManager {
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

    constructor(address payable ownerAddress, address _tokenAddress) {
        require(ownerAddress != address(0));
        require(_tokenAddress != address(0));

        owner = ownerAddress;
        tokenAddress = _tokenAddress;
        lastCampaignID = 0;
    }

    receive() external payable{
        emit EtherReceived(msg.value, msg.sender);
    }

    function newAirdropCampaign(
        uint256 endsIn,
        uint256 amountForCampaign,
        uint256 whitelistFee,
        uint256 amountForEachUser,
        uint256 maxUserAmount,
        bool hasFixedAmount
    )
        public
        onlyOwner
        returns (AirdropCampaign)
    {
        require(amountForCampaign <= ERC20(tokenAddress).balanceOf(address(this)),
            "Not enough tokens for the new Campaign");
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
                hasFixedAmount
            );

        require(ERC20(tokenAddress).transfer(address(newInstance), amountForCampaign));

        campaigns.push(
            Campaign({
                campaignID: lastCampaignID,
                endDate: block.timestamp + endsIn,
                amountToAirdrop: amountForCampaign,
                fee: whitelistFee,
                fixedAmount: hasFixedAmount,
                amountForEachUser: amountForEachUser,
                campaignAddress: newInstance
            })
        );

        lastCampaignID++;

        emit NewAirdropCampaign(endsIn, amountForCampaign, address(newInstance));

        return newInstance;
    }

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
}

// to do refactor onlyOwner
contract AirdropCampaign {
    uint256 public tokenAmount = 0;
    uint256 public claimableSince;
    uint256 public maxParticipantAmount; // helps when fixedAmount is true
    uint256 public participantAmount = 0;
    uint256 public whitelistFee;
    uint256 public amountForEachUser;
    uint256 public ownerTokenWithdrawDate; // The date the owner can withdraw the tokens
    address payable owner;
    address payable airMan;
    address public tokenAddress;
    bool public fixedAmount;

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
    event ModifiedValue(string modifiedValue, uint256 newValue);

    constructor(
        uint256 endDate,
        uint256 _whitelistFee,
        uint256 amountForCampaign,
        uint256 _maxParticipantAmount,
        uint256 valueForEachUser,  // can be 0
        address payable ownerAddress,
        address _tokenAddress,
        address payable airManAddress,
        bool hasFixedAmount
    )
    {
        require(ownerAddress != address(0));
        require(_tokenAddress != address(0));

        claimableSince = endDate;
        whitelistFee = _whitelistFee;
        tokenAmount = amountForCampaign;
        maxParticipantAmount = _maxParticipantAmount;
        amountForEachUser = valueForEachUser;
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
        airMan = airManAddress;
        ownerTokenWithdrawDate = claimableSince + (claimableSince - block.timestamp);
        fixedAmount = hasFixedAmount;
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

    function updateValue(uint8 option, uint256 newValue) external onlyOwner {
        string memory modifiedValue = '';

        if (option == 0) {
            whitelistFee = newValue;
            modifiedValue = 'whitelistFee';
        } else if (option == 1) {
            maxParticipantAmount = newValue;
            modifiedValue = 'maxParticipantAmount';
        } else if (option == 2) {
            amountForEachUser = newValue;
            modifiedValue = 'amountForEachUser';
        } else {
            revert('Only accepts from 0 to 2');
        }

        emit ModifiedValue(modifiedValue, newValue);
    }

    function toggleParticipation(address PartAddr) external onlyOwner {
        require(block.timestamp <= claimableSince, "Can't modify users, time is up");
        require(participantInfo[PartAddr].ParticipantAddress == PartAddr,
            "Participant doesn't exists");

        participantInfo[PartAddr].isBanned = !(participantInfo[PartAddr].isBanned);

        emit UserParticipationToggled(PartAddr, participantInfo[PartAddr].isBanned);
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
        require(msg.value == whitelistFee,
            'Exact fee not sent');
        _addToWhitelist(msg.sender);
    }

    function receiveTokens() external {
        require(block.timestamp >= claimableSince, 'Airdrop not claimable yet');
        require(participantInfo[msg.sender].isBanned == false, "You can't claim this airdrop");
        require(participantInfo[msg.sender].claimed == false,
            'You already claimed');

        uint256 _ToSend;
        if (fixedAmount) {
            _ToSend = amountForEachUser;
        } else {
            _ToSend = tokenAmount / participantAmount;
        }

        participantInfo[msg.sender].claimed = true;
        require(ERC20(tokenAddress).transfer(msg.sender, _ToSend));

        emit TokenClaimed(msg.sender, _ToSend);
    }

    function retireFromCampaign() public {
        require(participantInfo[msg.sender].ParticipantAddress == msg.sender,
            'You are not participating');
        require(block.timestamp <= claimableSince,
            'Campaign over, can not retire');
        participantInfo[msg.sender].ParticipantAddress = address(0); // user information is no longer tracked

        payable(msg.sender).transfer(whitelistFee);
    }

    function _addToWhitelist(address PartAddr) internal { // ** related
        require(PartAddr != address(0));
        require(block.timestamp <= claimableSince,
            'Campaign ended');
        require(participantInfo[PartAddr].ParticipantAddress != PartAddr,
            'Participant already exists');
        if (fixedAmount) {
            require(participantAmount + 1 <= maxParticipantAmount,
            "Can't join, whitelist is full");
        }
        participantInfo[PartAddr].ParticipantAddress = PartAddr;
        participantInfo[PartAddr].claimed = false;

        participantAmount++;

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