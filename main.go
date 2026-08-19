package main

import (
	"context"
	"log"

	"github.com/hashicorp/terraform-plugin-framework/providerserver"

	frameworkprovider "terraform-provider-fortiappseccloud/internal/provider"
)

const providerAddress = "registry.terraform.io/sqaz91819/fas-dev"

var (
	version = "dev"
	commit  = "unknown"
)

func main() {
	if err := providerserver.Serve(context.Background(), frameworkprovider.New(version, commit), providerserver.ServeOpts{Address: providerAddress, ProtocolVersion: 5}); err != nil {
		log.Fatalf("serve provider: %v", err)
	}
}
