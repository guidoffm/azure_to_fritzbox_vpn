variable "fritzbox_fqdn" {
  description = "MyFritz FQDN der FritzBox" 
}

variable "fritzbox_subnet" {
    description = "Subnet der FritzBox"
    default = "192.168.178.0/24"
}