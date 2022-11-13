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
    event NewAirdropManagerDeployed(address payable managerOwner, address tokenAddress);

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    constructor(uint256 _feeInGwei) {
        owner = payable(msg.sender);
        feeInGwei = _feeInGwei;
    }

    receive() external payable{
        // to do fix this
        payable(msg.sender).transfer(msg.value);
    }

    fallback() external payable{
        // to do fix this
        payable(msg.sender).transfer(msg.value);
    }

    function newAirdropManagerInstance(address instanceToken, uint256 initialBalance) public payable 
    returns (AirdropManager) 
    {
        require(msg.value == feeInGwei, 
            'AdminPanel.newAirdropManagerInstance: You need to deposit the minimum fee');
        require(ERC20(instanceToken).transferFrom(msg.sender, address(this), initialBalance),
            'AirdropManager.newAirdropCampaign: You need to be able to send tokens to the new Campaign');    
        
        AirdropManager newInstance = new AirdropManager(payable(msg.sender), instanceToken);
        ERC20(instanceToken).transfer(address(newInstance), initialBalance);

        deployedManagers.push(
            AirManInstance({
                owner: msg.sender,
                instanceAddress: address(newInstance),
                instanceToken: instanceToken
            })
        );

        emit NewAirdropManagerDeployed(payable(msg.sender), instanceToken);

        return newInstance;
    }

    function withdrawEther() external OnlyOwner {
        // to do optimize this
        uint amountToSend = address(this).balance;
        owner.transfer(amountToSend);

        emit EtherWithdrawed(amountToSend);
    }
}


contract AirdropManager {
    address payable owner;
    address tokenAddress;
    bool public isTokenSet = false;
    uint256 internal lastCampaignID = 0;
    Campaign[] public campaigns;

    struct Campaign {
        uint256 campaignID;
        uint256 endDate;
        AirdropCampaign campaignAddress;
        uint256 amountToAirdrop;
        bool isCampaignActive;
    }

    event NewAirdropCampaign(uint256 endsIn, uint256 amountToAirdrop);

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    constructor(address payable ownerAddress, address _tokenAddress) {
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
    }
    
    function newAirdropCampaign(uint endsIn, uint256 amountForCampaign) public OnlyOwner 
    returns (AirdropCampaign) 
    {
        require(amountForCampaign <= ERC20(tokenAddress).balanceOf(address(this)),
            'AirdropManager.newAirdropCampaign: Not enought tokens to fund this campaign');
        AirdropCampaign newInstance = 
            new AirdropCampaign(payable(address(this)), block.timestamp + endsIn, tokenAddress);

        ERC20(tokenAddress).transfer(address(newInstance), amountForCampaign);

        campaigns.push(
            Campaign({
                campaignID: lastCampaignID,
                endDate: block.timestamp + endsIn,
                campaignAddress: newInstance,
                amountToAirdrop: amountForCampaign,
                isCampaignActive: true
            })
        );

        lastCampaignID++;

        emit NewAirdropCampaign(endsIn, amountForCampaign);

        return newInstance;
    }

    function toggleCampaign(uint256 campaignID) external OnlyOwner {
        require(campaignID <= lastCampaignID, 
            'AirdropManager.toggleCampaign: This campaign ID does not exist');
        AirdropCampaign(campaigns[campaignID].campaignAddress).toggleIsActive();
    }

    function toggleParticipation(uint256 campaignID, address PartAddr) external OnlyOwner {
        require(campaignID <= lastCampaignID, 
            'AirdropManager.toggleParticipation: This campaign ID does not exist');
        AirdropCampaign(campaigns[campaignID].campaignAddress).toggleParticipation(PartAddr);
    }
}

contract AirdropCampaign {
    address payable owner;
    address tokenAddress;
    bool public acceptPayableWhitelist;
    uint256 public whitelistFee;
    uint256 public participantAmount = 0;
    bool public isActive;
    uint256 public claimableSince;
    
    struct Participant {
        address ParticipantAddress;
        bool isBanned;
        bool claimed;
    }

    mapping(address => Participant) public participantInfo;

    // to do events
    event CampaignStatusToggled(bool isActive_);
    event NewParticipant(address newParticipant);
    event EtherWithdrawed(uint256 amount);
    event TokenClaimed(address participantAddress, uint256 claimed);
    event UserParticipationToggled(address participantAddress, bool isBanned);

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    constructor(address payable ownerAddress, uint256 endDate, address _tokenAddress) {
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
        claimableSince = endDate;
        isActive = true;
    }

    receive() external payable{
        addToPayableWhitelist();
    }

    fallback() external payable{
        payable(msg.sender).transfer(msg.value);
    }

    function addToPayableWhitelist() public payable {
        require(acceptPayableWhitelist, 
            'AirdropCampaign.addToPayableWhitelist: Payable whitelist is not active');
        require(msg.value == whitelistFee,
            'AirdropCampaign.addToPayableWhitelist: You need to deposit the minimum fee');
        _addToWhitelist(msg.sender);
    }

    function addToWhitelist(address PartAddr) external OnlyOwner{
        _addToWhitelist(PartAddr);
    }

    function _addToWhitelist(address PartAddr) internal {
        require(isActive, 'AirdropCampaign._addToWhitelist: Campaign inactive');
        require(claimableSince <= block.timestamp, 'AirdropCampaign._addToWhitelist: Campaign inactive');
        require(participantInfo[PartAddr].ParticipantAddress != PartAddr, 
            'AirdropCampaign._addToWhitelist: Participant already exists');
        participantInfo[PartAddr].ParticipantAddress = PartAddr;
        participantInfo[PartAddr].isBanned = false;
        participantInfo[PartAddr].claimed = false;

        participantAmount++;

        emit NewParticipant(PartAddr);
    }

    function toggleParticipation(address PartAddr) external OnlyOwner {
        require(participantInfo[PartAddr].ParticipantAddress == PartAddr, 
            "AirdropCampaign._addToWhitelist: Participant doesn't exists");

        if (participantInfo[PartAddr].isBanned == true) {
            participantInfo[PartAddr].isBanned = false;
        } else {
            participantInfo[PartAddr].isBanned = true;
        }

        emit UserParticipationToggled(PartAddr, participantInfo[PartAddr].isBanned);
    }

    function toggleIsActive() external OnlyOwner {
        if (isActive == true) {
            isActive = false;
        } else {
            isActive = true;
        }

        emit CampaignStatusToggled(isActive);
    }

    // to do all this
    function receiveTokens() external {
        require(block.timestamp >= claimableSince, 'AirdropCampaign: Campaign inactive');
        require(participantInfo[msg.sender].isBanned == false, 'AirdropCampaign: You are banned');

        uint256 _ToSend = ERC20(tokenAddress).balanceOf(address(this)) / 
            participantAmount;
        participantInfo[msg.sender].claimed = true;
        ERC20(tokenAddress).transfer(msg.sender, _ToSend);

        emit TokenClaimed(msg.sender, _ToSend);
    }

    function withdrawEther() external OnlyOwner {
        // to do optimize this
        uint amountToSend = address(this).balance;
        owner.transfer(amountToSend);

        emit EtherWithdrawed(amountToSend);
    }
}


interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function Mint(address _MintTo, uint256 _MintAmount) external;
    function transfer(address to, uint256 value) external;
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
    function totalSupply() external view returns (uint256);
    function CheckMinter(address AddytoCheck) external view returns (uint256);
}