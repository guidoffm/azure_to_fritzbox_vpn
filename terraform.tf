# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  # resource_provider_registrations = "none" # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
  subscription_id = "55b4ce80-c422-409f-8712-d48a09e49a70"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = "network"
  location = "West Europe"
}


# resource "azurerm_network_security_group" "example" {
#   name                = "example-security-group"
#   location            = azurerm_resource_group.example.location
#   resource_group_name = azurerm_resource_group.example.name
# }

resource "azurerm_virtual_network" "example" {
  name                = "example-network"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.5.0.0/24"]
  # dns_servers         = ["10.0.0.4", "10.0.0.5"]

  subnet {
    name             = "DefaultSubnet"
    address_prefixes = ["10.5.0.0/25"]
  }

  subnet {
    name             = "GatewaySubnet"
    address_prefixes = ["10.5.0.128/25"]
    # security_group = azurerm_network_security_group.example.id
  }

  tags = {
    environment = "Production"
  }
}

resource "azurerm_local_network_gateway" "home" {
  name                = "AzureToFritBoxVPN-LNG"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  gateway_fqdn        = var.fritzbox_fqdn
  address_space       = [var.fritzbox_subnet] # Adressbereich des Heimnetzwerks
}

resource "azurerm_public_ip" "example" {
  name                = "AzureToFritzBoxVPN-PIP"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

resource "azurerm_virtual_network_gateway" "example" {
  name                = "AzureToFritzBoxVPN-VNG"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  type     = "Vpn"
  vpn_type = "PolicyBased"

  active_active = false
  enable_bgp    = false
  sku           = "Basic"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.example.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = "${azurerm_virtual_network.example.id}/subnets/GatewaySubnet"
  }
}

resource "azurerm_virtual_network_gateway_connection" "example" {
  name                = "example-connection"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  virtual_network_gateway_id = azurerm_virtual_network_gateway.example.id
  type                       = "IPsec"
  connection_protocol        = "IKEv1"

  shared_key = random_password.password.result
  local_network_gateway_id = azurerm_local_network_gateway.home.id
}

resource "random_password" "password" {
  length           = 64
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  file_content  = <<HERE
vpncfg {
        connections {
                enabled = yes;
                conn_type = conntype_lan;
                name = "AzureToFritzBoxVPN";
                always_renew = no;
                reject_not_encrypted = no;
                dont_filter_netbios = yes;
                localip = 0.0.0.0;
                local_virtualip = 0.0.0.0;
                remoteip = ${azurerm_public_ip.example.ip_address};
                remote_virtualip = 0.0.0.0;
                localid {
                        fqdn = "${var.fritzbox_fqdn}";
                }
                remoteid {
                        ipaddr = ${azurerm_public_ip.example.ip_address};
                }
                mode = phase1_mode_aggressive;
                phase1ss = "all/all/all";
                keytype = connkeytype_pre_shared;
                key = "${random_password.password.result}";
                cert_do_server_auth = no;
                use_nat_t = yes;
                use_xauth = no;
                use_cfgmode = no;
                phase2localid {
                        ipnet {
                                ipaddr = ${cidrhost(var.fritzbox_subnet, 0)};
                                mask = ${cidrnetmask(var.fritzbox_subnet)};
                        }
                }
                phase2remoteid {
                        ipnet {
                                ipaddr = 10.5.0.128;
                                mask = 255.255.255.128;
                        }
                }
                phase2ss = "esp-all-all/ah-none/comp-all/no-pfs";
                accesslist = "permit ip any 10.5.0.0 255.255.255.0";
        }
        ike_forward_rules = "udp 0.0.0.0:500 0.0.0.0:500", 
                            "udp 0.0.0.0:4500 0.0.0.0:4500";
}
HERE
}

# output "public_ip_address" {
#   value = azurerm_public_ip.example.ip_address
# }

resource "local_file" "example" {
  content  = local.file_content
  filename = "${path.module}/ipseccfg.txt"
}

resource "azurerm_network_interface" "example" {
  name                = "example-nic"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = "${azurerm_virtual_network.example.id}/subnets/DefaultSubnet"
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "example" {
  name                = "example-machine"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  size                = "Standard_A2m_v2"
  admin_username      = "adminuser"
  admin_password      = "P@$$w0rd1234!"
  network_interface_ids = [
    azurerm_network_interface.example.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
}