package main

import (
    "fmt"
    "encoding/json"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// SmartContract provides functions for managing parking spots
type SmartContract struct {
    contractapi.Contract
}

// ParkingSpot describes basic details of what makes up a parking spot
type ParkingSpot struct {
    ID     string `json:"id"`
    Status string `json:"status"` // 'occupied' or 'available'
    Zone   string `json:"zone"`
}

// InitLedger adds a base entry when chaincode starts
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
    return nil
}

// UpdateSpotStatus updates the status of a parking spot
func (s *SmartContract) UpdateSpotStatus(ctx contractapi.TransactionContextInterface, spotId string, status string, zone string) error {
    if len(spotId) == 0 {
        return fmt.Errorf("SpotID cannot be empty")
    }

    spot := ParkingSpot{
        ID:     spotId,
        Status: status,
        Zone:   zone,
    }

    spotJSON, err := json.Marshal(spot)
    if err != nil {
        return err
    }

    return ctx.GetStub().PutState(spotId, spotJSON)
}

// ReadSpot returns the spot stored in the world state with given id
func (s *SmartContract) ReadSpot(ctx contractapi.TransactionContextInterface, spotId string) (*ParkingSpot, error) {
    spotJSON, err := ctx.GetStub().GetState(spotId)
    if err != nil {
        return nil, fmt.Errorf("failed to read from world state: %v", err)
    }
    if spotJSON == nil {
        return nil, fmt.Errorf("the spot %s does not exist", spotId)
    }

    var spot ParkingSpot
    err = json.Unmarshal(spotJSON, &spot)
    if err != nil {
        return nil, err
    }

    return &spot, nil
}

// GetAllSpots returns all spots found in world state
func (s *SmartContract) GetAllSpots(ctx contractapi.TransactionContextInterface) ([]*ParkingSpot, error) {
    // Query dengan range kosong akan mengambil semua data
    resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
    if err != nil {
        return nil, err
    }
    defer resultsIterator.Close()

    var spots []*ParkingSpot
    for resultsIterator.HasNext() {
        queryResponse, err := resultsIterator.Next()
        if err != nil {
            return nil, err
        }

        var spot ParkingSpot
        err = json.Unmarshal(queryResponse.Value, &spot)
        if err != nil {
            return nil, err
        }
        spots = append(spots, &spot)
    }

    return spots, nil
}

func main() {
    chaincode, err := contractapi.NewChaincode(&SmartContract{})
    if err != nil {
        fmt.Printf("Error creating parking chaincode: %s", err.Error())
        return
    }

    if err := chaincode.Start(); err != nil {
        fmt.Printf("Error starting parking chaincode: %s", err.Error())
    }
}