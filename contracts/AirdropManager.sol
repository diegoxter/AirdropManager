//SPDX-License-Identifier:UNLICENSE
pragma solidity ^0.8.16;

contract AdminPanel {
    address payable public owner;
    uint public feeInGwei;
    AirManInstance[] public deployedManagers; // TO DO check if this is still needed
    uint256 public instanceIDs = 0;

    struct AirManInstance {
        address owner;
        uint id;
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

    constructor(uint256 _feeInGwei) {
        owner = payable(msg.sender);
        feeInGwei = _feeInGwei;
    }

    receive() external payable{
        revert();
    }

    fallback() external payable{
        revert();
    }

    function freeAirManInstace(address _instanceToken, uint256 _initialBalance, address payable _newOwner) external onlyOwner {
        _deployNewAirMan(_instanceToken, _initialBalance, _newOwner);
    }

    function setFeeInGwei(uint256 newFeeInGwei) external onlyOwner {
        feeInGwei = newFeeInGwei;

        emit NewFee(newFeeInGwei);
    }

    function getDeployedInstances(address instanceOwner) public view returns (uint256[] memory) {
        uint256[] memory instances = new uint256[](deployedByUser[instanceOwner].length);
        
        for (uint256 i = 0; i < deployedByUser[instanceOwner].length; i++) {
            instances[i] = deployedByUser[instanceOwner][i].id;
        }

        return instances;
    }

    function newAirdropManagerInstance(address _instanceToken, uint256 _initialBalance) public payable 
    {
        require(msg.value == feeInGwei, 
            'Minimum fee not sent'); 
        
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
        instance.owner = _newOwner;
        instance.id = instanceIDs;
        instance.instanceAddress = address(newInstance);
        instance.instanceToken = _instanceToken;

        deployedManagers.push(instance); // TO DO check if this is still needed
        deployedByUser[_newOwner].push(instance);

        instanceIDs++;

        emit NewAirdropManagerDeployed(payable(msg.sender), _instanceToken, address(newInstance));
    }

    function withdrawEther() external onlyOwner {
        // to do optimize this
        uint amountToSend = address(this).balance;
        owner.transfer(amountToSend);

        emit EtherWithdrawed(amountToSend);
    }
}


contract AirdropManager {
    address payable public owner;
    address public tokenAddress;
    uint256 internal lastCampaignID = 0;
    Campaign[] public campaigns;
    // TO DO add a function to track the airdrops a user has been part of

    struct Campaign {
        uint256 campaignID;
        uint256 endDate;
        AirdropCampaign campaignAddress;
        uint256 amountToAirdrop;
        bool fixedAmount;
        uint256 amountForEachUser; // can be 0
    }

    event NewAirdropCampaign(uint256 endsIn, uint256 amountToAirdrop);
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
    }
    
    function newAirdropCampaign(
        uint endsIn, 
        uint256 amountForCampaign,
        bool hasFixedAmount, 
        uint256 amountForEveryUser
    ) 
        public 
        onlyOwner 
        returns (AirdropCampaign) 
    {
        require(amountForCampaign <= ERC20(tokenAddress).balanceOf(address(this)),
            "Not enough tokens for the new Campaign");
        require(amountForCampaign > amountForEveryUser); // to do what?
        require(endsIn > 0);
        AirdropCampaign newInstance = 
            new AirdropCampaign(
                owner, 
                block.timestamp + endsIn, 
                tokenAddress, 
                hasFixedAmount, 
                amountForEveryUser, 
                amountForCampaign,
                address(this)
            );

        require(ERC20(tokenAddress).transfer(address(newInstance), amountForCampaign));

        campaigns.push(
            Campaign({
                campaignID: lastCampaignID,
                endDate: block.timestamp + endsIn,
                campaignAddress: newInstance,
                amountToAirdrop: amountForCampaign,
                fixedAmount: hasFixedAmount,
                amountForEachUser: amountForEveryUser
            })
        );
        
        lastCampaignID++;

        emit NewAirdropCampaign(endsIn, amountForCampaign);

        return newInstance;
    }

    // to do unify these withdrawing functions

    /// @param option: Can be 0 for ether or 1 for tokens
    function manageFunds(uint8 option) external onlyOwner {
            if (option == 0) { // Withdraw Ether
                // to do optimize this
                uint amountToSend = address(this).balance;
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
    address payable owner;
    address public airMan;
    address tokenAddress;
    uint256 tokenAmount = 0;
    bool public isActive;
    uint256 public claimableSince;
    bool public acceptPayableWhitelist = false;
    uint256 public whitelistFee;
    uint256 public participantAmount = 0;
    uint256 public maxParticipantAmount; // helps when fixedAmount is true
    bool public fixedAmount;
    uint256 public amountForEachUser;
    uint256 public ownerTokenWithdrawDate; // The date the owner can withdraw the tokens

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    struct Participant {
        address ParticipantAddress;
        bool canReceive;
        bool claimed;
    }

    mapping(address => Participant) public participantInfo;

    event CampaignStatusToggled(bytes18 optionToggled, bool isActive_);
    event NewParticipant(address newParticipant);
    event EtherWithdrawed(uint256 amount);
    event TokenClaimed(address participantAddress, uint256 claimed);
    event UserParticipationToggled(address participantAddress, bool isBanned);
    event WithdrawedTokens(uint256 Amount);
    event ModifiedValue(string modifiedValue, uint256 newValue);

    constructor(
        address payable ownerAddress, 
        uint256 endDate, 
        address _tokenAddress, 
        bool hasFixedAmount,
        uint256 valueForEachUser,  // can be 0
        uint256 amountForCampaign,
        address airManAddress
    ) 
    {
        require(ownerAddress != address(0));
        require(_tokenAddress != address(0));

        owner = ownerAddress;
        airMan = airManAddress;
        tokenAddress = _tokenAddress;
        claimableSince = endDate;
        ownerTokenWithdrawDate = claimableSince + (claimableSince - block.timestamp);
        isActive = true;
        fixedAmount = hasFixedAmount;
        tokenAmount = amountForCampaign;

        if (hasFixedAmount) 
            amountForEachUser = valueForEachUser;
    }

    receive() external payable{
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

        if (participantInfo[PartAddr].canReceive == true) {
            participantInfo[PartAddr].canReceive = false;
            participantAmount--;
        } else {
            participantInfo[PartAddr].canReceive = true;
            participantAmount++;
        }

        emit UserParticipationToggled(PartAddr, participantInfo[PartAddr].canReceive);
    }

    /// @param option: 0 isActive 1 acceptPayableWhitelist
    function toggleOption(uint8 option) external onlyOwner {
            if (option == 0) { // isActive
                require(block.timestamp <= claimableSince, 
                    "Can't modify users, time is up");

                if (isActive == true) {
                    isActive = false;
                } else {
                    isActive = true;
                }

                emit CampaignStatusToggled('Is active?', isActive);
            } else if (option == 1) { // acceptPayableWhitelist
                if (acceptPayableWhitelist == true) {
                    acceptPayableWhitelist = false;
                } else {
                    acceptPayableWhitelist = true;
                }

                emit CampaignStatusToggled('Payable Whitelist?', acceptPayableWhitelist);
            }
    }

    function manageFunds(uint8 option, bool toOwner) external onlyOwner {
         if (option == 0) { // Withdraw Ether
                require(block.timestamp >= claimableSince, 
                    'Ether not claimable yet');
                // to do optimize this
                uint amountToSend = address(this).balance;
                owner.transfer(amountToSend);

                emit EtherWithdrawed(amountToSend);
            } else if (option == 1) { // Withdraw Tokens
                require(block.timestamp >= ownerTokenWithdrawDate, 
                    'Tokens not claimable yet');
                uint256 toSend = ERC20(tokenAddress).balanceOf(address(this));
                if (toOwner) {
                    require(ERC20(tokenAddress).transfer(owner, toSend));
                } else {
                    require(ERC20(tokenAddress).transfer(airMan, toSend));
                }

                emit WithdrawedTokens(toSend);
            } else {
                revert('Only accepts 0 or 1');
            }
    }

    // User functions
    function addToPayableWhitelist() public payable { // This is payable but if fee is 0 then its free
        require(acceptPayableWhitelist, 
            'Payable whitelist not active');
        require(msg.value == whitelistFee,
            'Minimum fee not sent');
        _addToWhitelist(msg.sender); 
    }

    function receiveTokens() external {
        require(block.timestamp >= claimableSince, 'Airdrop not claimable yet');
        require(participantInfo[msg.sender].canReceive == true, "You can't claim this airdrop");
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

    // to do test this
    function retireFromCampaign() public {
        require(participantInfo[msg.sender].canReceive,
            'You are not participating');
        require(block.timestamp <= claimableSince,
            'Campaign over, can not retire');
        participantInfo[msg.sender].canReceive = false; // we soft ban the user, to keep spammers out
        // to do optimize this
        payable(msg.sender).transfer(whitelistFee);
    }

    function _addToWhitelist(address PartAddr) internal { // ** related
        require(PartAddr != address(0));
        require(isActive, 'Campaign inactive');
        require(block.timestamp <= claimableSince, 
            'Campaign ended');
        require(participantInfo[PartAddr].ParticipantAddress != PartAddr, 
            'Participant already exists');
        if (fixedAmount) {
            require(participantAmount + 1 <= maxParticipantAmount,
            "Can't join, whitelist is full");
        }
        participantInfo[PartAddr].ParticipantAddress = PartAddr;
        participantInfo[PartAddr].canReceive = true;
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