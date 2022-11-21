//SPDX-License-Identifier:UNLICENSE
pragma solidity ^0.8.17;

contract AdminPanel {
    address payable public owner;
    uint public feeInGwei;
    AirManInstance[] public deployedManagers;

    struct AirManInstance {
        address owner;
        address instanceAddress;
        address instanceToken;
    }

    event EtherWithdrawed(uint256 amount);
    event NewAirdropManagerDeployed(address payable managerOwner, address tokenAddress, address deployedManager);

    modifier OnlyOwner() {
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

    function newAirdropManagerInstance(address instanceToken, uint256 initialBalance) public payable 
    {
        require(msg.value == feeInGwei, 
            'AdminPanel.newAirdropManagerInstance: Minimum fee not sent');
        require(ERC20(instanceToken).allowance(msg.sender, address(this)) >= initialBalance,
            'AirdropManager.newAirdropManagerInstance: No tokens sent to new Campaign');    
        
        _deployNewAirMan(instanceToken, initialBalance, payable(msg.sender));
    }

    function freeAirManInstace(address instanceToken, uint256 initialBalance, address payable _owner) external OnlyOwner {
        _deployNewAirMan(instanceToken, initialBalance, _owner);
    }

    function _deployNewAirMan(address instanceToken, uint256 initialBalance, address payable newOwner) internal {
        AirdropManager newInstance = new AirdropManager(newOwner, instanceToken);
        ERC20(instanceToken).transferFrom(newOwner, address(newInstance), initialBalance);  
        
        deployedManagers.push(
            AirManInstance({
                owner: newOwner,
                instanceAddress: address(newInstance),
                instanceToken: instanceToken
            })
        );

        emit NewAirdropManagerDeployed(payable(msg.sender), instanceToken, address(newInstance));
    }

    function withdrawEther() external OnlyOwner {
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

    struct Campaign {
        uint256 campaignID;
        uint256 endDate;
        AirdropCampaign campaignAddress;
        uint256 amountToAirdrop;
        bool isCampaignActive;
        bool fixedAmount;
        uint256 amountForEachUser; // can be 0
    }

    event NewAirdropCampaign(uint256 endsIn, uint256 amountToAirdrop);
    event EtherWithdrawed(uint256 amount);
    event WithdrawedTokens(uint256 Amount);

    modifier OnlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(address payable ownerAddress, address _tokenAddress) {
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
    }
    
    function newAirdropCampaign(uint endsIn, uint256 amountForCampaign, bool hasFixedAmount, uint256 amountForEveryUser) public OnlyOwner 
    returns (AirdropCampaign) 
    {
        require(amountForCampaign <= ERC20(tokenAddress).balanceOf(address(this)),
            'AirMan.newAirdropCampaign: Not enough tokens to fund campaign');
        require(amountForCampaign > amountForEveryUser);
        AirdropCampaign newInstance = 
            new AirdropCampaign(payable(address(this)), block.timestamp + endsIn, tokenAddress, hasFixedAmount, amountForEveryUser);

        ERC20(tokenAddress).transfer(address(newInstance), amountForCampaign);

        campaigns.push(
            Campaign({
                campaignID: lastCampaignID,
                endDate: block.timestamp + endsIn,
                campaignAddress: newInstance,
                amountToAirdrop: amountForCampaign,
                isCampaignActive: true,
                fixedAmount: hasFixedAmount,
                amountForEachUser: amountForEveryUser
            })
        );
        
        AirdropCampaign(campaigns[lastCampaignID].campaignAddress).updateValue(3, 0);

        lastCampaignID++;

        emit NewAirdropCampaign(endsIn, amountForCampaign);

        return newInstance;
    }

    function batchAddToWhitelist(uint256 campaignID, address[] memory PartAddr) external OnlyOwner{
        require(campaignID <= lastCampaignID, 
            'AirMan.toggleCampaign: This ID does not exist');
        AirdropCampaign(campaigns[campaignID].campaignAddress).batchAddToWhitelist(PartAddr);
    }

    function toggleCampaignOption(uint256 campaignID, uint8 option) external OnlyOwner {
        require(option >=0 && option <= 1, 
            'AirMan.toggleCampaignOption: Only accepts 0 or 1');

        AirdropCampaign(campaigns[campaignID].campaignAddress).toggleOption(option);

        if (option == 0) {
            campaigns[campaignID].isCampaignActive = 
            AirdropCampaign(campaigns[campaignID].campaignAddress).isActive();    
        }
    }

    function updateCampaignValue(uint256 campaignID, uint8 option, uint256 newValue) external OnlyOwner {
        require(campaignID <= lastCampaignID, 
            'AirMan.toggleCampaign: This ID does not exist');

        require(option >=0 && option <= 3, 
            'AirMan.toggleCampaignOption: Only accepts 0 or 1');

            AirdropCampaign(campaigns[campaignID].campaignAddress).updateValue(option, newValue);

    }

    function toggleParticipation(uint256 campaignID, address PartAddr) external OnlyOwner {
        require(campaignID <= lastCampaignID, 
            'AirMan.toggleParticipation: This ID does not exist');
        AirdropCampaign(campaigns[campaignID].campaignAddress).toggleParticipation(PartAddr);
    }

    // to do unify this withdrawing functions

    /// @param option: Can be 0 for ether or 1 for tokens
    function manageFunds(bool ofManager, uint8 option, uint256 campaignID) external OnlyOwner {
        if (ofManager) { // AirMan instance
            if (option == 0) { // Withdraw Ether
                // to do optimize this
                uint amountToSend = address(this).balance;
                owner.transfer(amountToSend);

                emit EtherWithdrawed(amountToSend);
            } else if (option == 1) { // Withdraw Tokens
                uint256 toSend = ERC20(tokenAddress).balanceOf(address(this));
                ERC20(tokenAddress).transfer(owner, toSend);

                emit WithdrawedTokens(toSend);
            } else {
                revert('Only accepts 0 or 1');
            }
        } else { // Airdrop Campaign instance
            if (option == 0) { // Withdraw Ether
                require(campaignID <= lastCampaignID, 
                    'AirMan.toggleParticipation: This ID does not exist');
                AirdropCampaign(campaigns[campaignID].campaignAddress).withdrawEther();
            } else if (option == 1) { // Withdraw Tokens
                require(campaignID <= lastCampaignID, 
                    'AirMan.toggleParticipation: This ID does not exist');
                AirdropCampaign(campaigns[campaignID].campaignAddress).withdrawTokens();
            } else {
                revert('Only accepts 0 or 1');
            }
        }
    }
}


contract AirdropCampaign {
    address payable owner;
    address tokenAddress;
    bool public isActive;
    uint256 public claimableSince;
    uint256 public tokenBalance;
    bool public acceptPayableWhitelist = false;
    uint256 public whitelistFee;
    uint256 public participantAmount = 0;
    uint256 public maxParticipantAmount; // helps when fixedAmount is true
    bool public fixedAmount;
    uint256 public amountForEachUser;
    uint256 public ownerTokenWithdrawDate; // The date the owner can withdraw the tokens

    modifier OnlyOwner() {
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
        uint256 valueForEachUser  // can be 0
    ) 
    {
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
        claimableSince = endDate;
        ownerTokenWithdrawDate = claimableSince + (claimableSince - block.timestamp);
        isActive = true;
        fixedAmount = hasFixedAmount;

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
    function batchAddToWhitelist(address[] memory PartAddr) external OnlyOwner{
        for (uint256 id = 0; id < PartAddr.length; ++id) {
            _addToWhitelist(PartAddr[id]);
        }
    }

    function updateValue(uint8 option, uint256 newValue) external OnlyOwner {
        string memory modifiedValue;

        if (option == 0) {
            whitelistFee = newValue;
            modifiedValue = 'whitelistFee';
        } else if (option == 1) {
            maxParticipantAmount = newValue;
            modifiedValue = 'maxParticipantAmount';
        } else if (option == 2) {
            amountForEachUser = newValue;
            modifiedValue = 'amountForEachUser';
        } else if (option == 3) {
            tokenBalance = ERC20(tokenAddress).balanceOf(address(this));
            modifiedValue = 'tokenBalance';
        }

        emit ModifiedValue(modifiedValue, newValue);
    }

    function toggleParticipation(address PartAddr) external OnlyOwner {
        require(block.timestamp <= claimableSince, "AirdropCampaign.toggleIsActive: Can't modify users, time is up");
        require(participantInfo[PartAddr].ParticipantAddress == PartAddr, 
            "AirdropCampaign.toggleParticipation: Participant doesn't exists");

        if (participantInfo[PartAddr].canReceive == true) {
            participantInfo[PartAddr].canReceive = false;
            participantAmount--;
        } else {
            participantInfo[PartAddr].canReceive = true;
            participantAmount++;
        }

        emit UserParticipationToggled(PartAddr, participantInfo[PartAddr].canReceive);
    }

    function toggleOption(uint8 option) external OnlyOwner {
            if (option == 0) { // isActive
                require(block.timestamp <= claimableSince, 
                    "AirdropCampaign.toggleIsActive: Can't modify users, time is up");

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

    function withdrawTokens() external OnlyOwner {
        require(block.timestamp >= ownerTokenWithdrawDate, 
            'AirdropCampaign.withdrawTokens: Tokens not claimable yet');
        uint256 toSend = ERC20(tokenAddress).balanceOf(address(this));
        ERC20(tokenAddress).transfer(owner, toSend);

        emit WithdrawedTokens(toSend);
    }

    function withdrawEther() external OnlyOwner {
        // to do optimize this
        uint amountToSend = address(this).balance;
        address payable airManOwner = AirdropManager(owner).owner();
        airManOwner.transfer(amountToSend);

        emit EtherWithdrawed(amountToSend);
    }

    // User functions
    function addToPayableWhitelist() public payable { // This is payable but if fee is 0 then its free
        require(acceptPayableWhitelist, 
            'AirdropCampaign.addToPayableWhitelist: Payable whitelist is not active');
        require(msg.value == whitelistFee,
            'AirdropCampaign.addToPayableWhitelist: Minimum fee not sent');
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
            _ToSend = tokenBalance / participantAmount;
        }

        participantInfo[msg.sender].claimed = true;
        ERC20(tokenAddress).transfer(msg.sender, _ToSend);

        emit TokenClaimed(msg.sender, _ToSend);
    }

    // to do a function for user to retire from a campaign 

    function _addToWhitelist(address PartAddr) internal { // ** related
        require(PartAddr != address(0), 
            'AirdropCampaign._addToWhitelist: Address zero can not join the Airdrop');
        require(isActive, 'AirdropCampaign._addToWhitelist: Campaign inactive');
        require(block.timestamp <= claimableSince, 
            'AirdropCampaign._addToWhitelist: Campaign ended');
        require(participantInfo[PartAddr].ParticipantAddress != PartAddr, 
            'AirdropCampaign._addToWhitelist: Participant already exists');
        if (fixedAmount) {
            require(participantAmount + 1 <= maxParticipantAmount,
            'AirdropCampaign._addToWhitelist.hasFixedAmount: Can not join, whitelist is full');
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
    function transfer(address to, uint256 value) external;
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}