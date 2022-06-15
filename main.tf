//Frank Sinoradzki
//This is intended to run within the Azure CLI
//Azure would not provision me a VM, so I was unable to test this
provider "azurerm" {
  features {}
}

//Local variables
//The two different location variables are to deploy the two networks 
//And VMs on two different regions.
locals {
  resource_group="app-grp"
  location1="East US" 
  location2="North Europe" 
}

//The resource group this is being deployed to
resource "azurerm_resource_group" "app_grp"{
  name=local.resource_group
  location=local.location1
}

//The first network
resource "azurerm_virtual_network" "app_networkA" {
  name                = "app-networkA"
  location            = local.location1
  resource_group_name = azurerm_resource_group.app_grp.name
  address_space       = ["10.0.0.0/16"]  
  depends_on = [
    azurerm_resource_group.app_grp
  ]
}

//The subnet on the first network
resource "azurerm_subnet" "SubnetA" {
  name                 = "SubnetA"
  resource_group_name  = azurerm_resource_group.app_grp.name
  virtual_network_name = azurerm_virtual_network.app_networkA.name
  address_prefixes     = ["10.0.0.0/24"]
  depends_on = [
    azurerm_virtual_network.app_networkA
  ]
}

//The NIC for appvm1
resource "azurerm_network_interface" "app_interface1" {
  name                = "app-interface1"
  location            = azurerm_resource_group.app_grp.location
  resource_group_name = azurerm_resource_group.app_grp.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.SubnetA.id
    private_ip_address_allocation = "Dynamic"    
  }

  depends_on = [
    azurerm_virtual_network.app_networkA,
    azurerm_subnet.SubnetA
  ]
}

//The NIC for appvm2
resource "azurerm_network_interface" "app_interface2" {
  name                = "app-interface2"
  location            = azurerm_resource_group.app_grp.location
  resource_group_name = azurerm_resource_group.app_grp.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.SubnetA.id
    private_ip_address_allocation = "Dynamic"    
  }

  depends_on = [
    azurerm_virtual_network.app_networkA,
    azurerm_subnet.SubnetA
  ]
}

//The first VM on the first host
resource "azurerm_windows_virtual_machine" "app_vm1" {
  name                = "appvm1"
  resource_group_name = azurerm_resource_group.app_grp.name
  location            = azurerm_resource_group.app_grp.location
  size                = "Standard_D2s_v3"
  admin_username      = "demousr"
  admin_password      = "Azure@123"
  availability_set_id = azurerm_availability_set.app_set.id
  network_interface_ids = [
    azurerm_network_interface.app_interface1.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.app_interface1,
    azurerm_availability_set.app_set
  ]
}

// This is the second VM on the first network
resource "azurerm_windows_virtual_machine" "app_vm2" {
  name                = "appvm2"
  resource_group_name = azurerm_resource_group.app_grp.name
  location            = azurerm_resource_group.app_grp.location
  size                = "Standard_D2s_v3"
  admin_username      = "demousr"
  admin_password      = "Azure@123"
  availability_set_id = azurerm_availability_set.app_set.id
  network_interface_ids = [
    azurerm_network_interface.app_interface2.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.app_interface2,
    azurerm_availability_set.app_set
  ]
}

//This sets the availability
resource "azurerm_availability_set" "app_set" {
  name                = "app-set"
  location            = azurerm_resource_group.app_grp.location
  resource_group_name = azurerm_resource_group.app_grp.name
  platform_fault_domain_count = 3
  platform_update_domain_count = 3  
  depends_on = [
    azurerm_resource_group.app_grp
  ]
}

//This creates a network security group
resource "azurerm_network_security_group" "app_nsg" {
  name                = "app-nsg"
  location            = azurerm_resource_group.app_grp.location
  resource_group_name = azurerm_resource_group.app_grp.name

  //This rule allows traffic on port 80
  security_rule {
    name                       = "Allow_HTTP"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

//This associates the security group with the subnet
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.SubnetA.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
  depends_on = [
    azurerm_network_security_group.app_nsg
  ]
}

//This creates a static public IP
resource "azurerm_public_ip" "load_ip" {
    name = "load-ip"
    location = azurerm_resource_group.app_grp.location
    resource_group_name = azurerm_resource_group.app_grp.name
    allocation_method = "Static"
}

//This is the app balancer, hosted on the aforementioned static public IP
resource "azurerm_lb" "app_balancer" {
    name = "app-balancer"
    location = azurerm_resource_group.app_grp.location
    resource_group_name = azurerm_resource_group.app_grp.name

    frontend_ip_configuration{
        name = "frontend-ip"
        public_ip_address_id = azurerm_public_ip.load_ip.id
    }

    depends_on = [
        azurerm_public_ip.load_ip
    ]
}

//This is the pool of backend addresses for the first load balancer
resource "azurerm_lb_backend_address_pool" "PoolA" {
    loadbalancer_id = azurerm_lb.app_balancer.id
    name = "PoolA"

    depends_on = [
        azurerm_lb.app_balancer
    ]
}

//This is the address of Pool A addresses for the first VM
resource "azurerm_lb_backend_address_pool_address" "appvm1_address" {
    name = "appvm1"
    backend_address_pool_id = azurerm_lb_backend_address_pool.PoolA.id
    virtual_network_id = azurerm_virtual_network.app_networkA.id
    ip_address = azurerm_network_interface.app_interface1.private_ip_address

    depends_on = [
        azurerm_lb_backend_address_pool.PoolA
    ]
}

//This is the address of Pool A addresses for the second VM
resource "azurerm_lb_backend_address_pool_address" "appvm2_address" {
    name = "appvm2"
    backend_address_pool_id = azurerm_lb_backend_address_pool.PoolA.id
    virtual_network_id = azurerm_virtual_network.app_networkA.id
    ip_address = azurerm_network_interface.app_interface2.private_ip_address
}

//This is the probe to see of the load balancer
resource "azurerm_lb_probe" "ProbeA" {
    resource_group_name = azurerm_resource_group.app_grp.name
    loadbalancer_id = azurerm_lb.app_balancer.id
    name = "ProbeA"
    port = 80
}

//This is the rule for the load balancer distributing traffic amongst the two VMs
//On the first network
resource "azurerm_lb_rule" "RuleA" {
    resource_group_name = azurerm_resource_group.app_grp.name
    loadbalancer_id = azurerm_lb.app_balancer.id
    name = "RuleA"
    protocol = "Tcp"
    frontend_port = 80
    backend_port = 80
    frontend_ip_configuration_name = "frontend-ip"
}

// Copied the above to initialize a second network set

//This is the second network
resource "azurerm_virtual_network" "app_networkB" {
    name                = "app-networkA"
    location            = local.location2
    resource_group_name = azurerm_resource_group.app_grp.name
    address_space       = ["10.0.0.0/16"]  
    depends_on = [
      azurerm_resource_group.app_grp
    ]
}

//This is a subnet on the second network
resource "azurerm_subnet" "SubnetB" {
    name                 = "SubnetB"
    resource_group_name  = azurerm_resource_group.app_grp.name
    virtual_network_name = azurerm_virtual_network.app_networkB.name
    address_prefixes     = ["10.0.0.0/24"]
    depends_on = [
      azurerm_virtual_network.app_networkB
    ]
}
  
//This is the NIC for the first VM on the second network
resource "azurerm_network_interface" "app_interface3" {
    name                = "app-interface3"
    location            = azurerm_resource_group.app_grp.location
    resource_group_name = azurerm_resource_group.app_grp.name
  
    ip_configuration {
      name                          = "internal"
      subnet_id                     = azurerm_subnet.SubnetB.id
      private_ip_address_allocation = "Dynamic"    
    }
  
    depends_on = [
      azurerm_virtual_network.app_networkB,
      azurerm_subnet.SubnetB
    ]
}
  
//This is the NIC for the second VM on the second network
resource "azurerm_network_interface" "app_interface4" {
    name                = "app-interface4"
    location            = azurerm_resource_group.app_grp.location
    resource_group_name = azurerm_resource_group.app_grp.name
  
    ip_configuration {
      name                          = "internal"
      subnet_id                     = azurerm_subnet.SubnetB.id
      private_ip_address_allocation = "Dynamic"    
    }
  
    depends_on = [
      azurerm_virtual_network.app_networkB,
      azurerm_subnet.SubnetB
    ]
}
  
//This is the first VM on the second network
resource "azurerm_windows_virtual_machine" "app_vm3" {
    name                = "appvm3"
    resource_group_name = azurerm_resource_group.app_grp.name
    location            = azurerm_resource_group.app_grp.location
    size                = "Standard_D2s_v3"
    admin_username      = "demousr"
    admin_password      = "Azure@123"
    availability_set_id = azurerm_availability_set.app_set2.id
    network_interface_ids = [
      azurerm_network_interface.app_interface3.id,
    ]
  
    os_disk {
      caching              = "ReadWrite"
      storage_account_type = "Standard_LRS"
    }
  
    source_image_reference {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2019-Datacenter"
      version   = "latest"
    }
  
    depends_on = [
      azurerm_network_interface.app_interface3,
      azurerm_availability_set.app_set2
    ]
}
  
//This is the second VM on the second network
resource "azurerm_windows_virtual_machine" "app_vm2" {
    name                = "appvm4"
    resource_group_name = azurerm_resource_group.app_grp.name
    location            = azurerm_resource_group.app_grp.location
    size                = "Standard_D2s_v3"
    admin_username      = "demousr"
    admin_password      = "Azure@123"
    availability_set_id = azurerm_availability_set.app_set2.id
    network_interface_ids = [
      azurerm_network_interface.app_interface4.id,
    ]
  
    os_disk {
      caching              = "ReadWrite"
      storage_account_type = "Standard_LRS"
    }
  
    source_image_reference {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2019-Datacenter"
      version   = "latest"
    }
  
    depends_on = [
      azurerm_network_interface.app_interface4,
      azurerm_availability_set.app_set2
    ]
}
  
//This sets the availailability of the second set of VMs
resource "azurerm_availability_set" "app_set2" {
    name                = "app-set2"
    location            = azurerm_resource_group.app_grp.location
    resource_group_name = azurerm_resource_group.app_grp.name
    platform_fault_domain_count = 3
    platform_update_domain_count = 3  
    depends_on = [
      azurerm_resource_group.app_grp
    ]
}

//This is a security group
resource "azurerm_network_security_group" "app_nsg2" {
    name                = "app-nsg2"
    location            = azurerm_resource_group.app_grp.location
    resource_group_name = azurerm_resource_group.app_grp.name
  
  //This allows traffic over port 80
    security_rule {
      name                       = "Allow_HTTP"
      priority                   = 200
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
}
  
//This associates the security group with Subnet B
resource "azurerm_subnet_network_security_group_association" "nsg_association2" {
    subnet_id                 = azurerm_subnet.SubnetB.id
    network_security_group_id = azurerm_network_security_group.app_nsg2.id
    depends_on = [
      azurerm_network_security_group.app_nsg2
    ]
}

//This creates a static public IP for the second load balancer
resource "azurerm_public_ip" "load_ip2" {
      name = "load-ip2"
      location = azurerm_resource_group.app_grp.location
      resource_group_name = azurerm_resource_group.app_grp.name
      allocation_method = "Static"
}

//This is the second load balancer
resource "azurerm_lb" "app_balancer2" {
      name = "app-balancer2"
      location = azurerm_resource_group.app_grp.location
      resource_group_name = azurerm_resource_group.app_grp.name
  
      frontend_ip_configuration{
          name = "frontend-ip2"
          public_ip_address_id = azurerm_public_ip.load_ip2.id
      }
  
      depends_on = [
          azurerm_public_ip.load_ip2
      ]
}

//This creates a pool of backend addresses for the second load balancer
resource "azurerm_lb_backend_address_pool" "PoolB" {
      loadbalancer_id = azurerm_lb.app_balancer2.id
      name = "PoolB"
  
      depends_on = [
          azurerm_lb.app_balancer2
      ]
}

//This is the address of pool B address for the first VM of the second network
resource "azurerm_lb_backend_address_pool_address" "appvm3_address" {
      name = "appvm3"
      backend_address_pool_id = azurerm_lb_backend_address_pool.PoolB.id
      virtual_network_id = azurerm_virtual_network.app_networkB.id
      ip_address = azurerm_network_interface.app_interface3.private_ip_address
  
      depends_on = [
          azurerm_lb_backend_address_pool.PoolB
      ]
}

//This is the address of pool B address for the second VM of the second network
resource "azurerm_lb_backend_address_pool_address" "appvm4_address" {
      name = "appvm4"
      backend_address_pool_id = azurerm_lb_backend_address_pool.PoolB.id
      virtual_network_id = azurerm_virtual_network.app_networkB.id
      ip_address = azurerm_network_interface.app_interface4.private_ip_address
}

//This is the health probe for the load balancer
resource "azurerm_lb_probe" "ProbeB" {
      resource_group_name = azurerm_resource_group.app_grp.name
      loadbalancer_id = azurerm_lb.app_balancer2.id
      name = "ProbeB"
      port = 80
}

//This is the rule for the load balancer distributing traffic amongst the two VMs
//On the second network
resource "azurerm_lb_rule" "RuleB" {
      resource_group_name = azurerm_resource_group.app_grp.name
      loadbalancer_id = azurerm_lb.app_balancer2.id
      name = "RuleB"
      protocol = "Tcp"
      frontend_port = 80
      backend_port = 80
      frontend_ip_configuration_name = "frontend-ip2"
}

//This is the traffic manager profile
resource "azurerm_traffic_manager_profile" "traffic_profile" {
  name                   = "traffic-profile2000"
  resource_group_name    = azurerm_resource_group.app_grp.name
  traffic_routing_method = "Priority"
   dns_config {
    relative_name = "traffic-profile2000"
    ttl           = 100
  }
  monitor_config {
    protocol                     = "https"
    port                         = 443
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 2
  }
}

//This is the endpoint for the first network
resource "azurerm_traffic_manager_azure_endpoint" "primary_endpoint" {
  name               = "primary-endpoint"
  profile_id         = azurerm_traffic_manager_profile.traffic_profile.id
  priority           = 1
  weight             = 100
  target_resource_id = azurerm_app_service.app_balancer.id
}

//This is the endpoint for the second network
resource "azurerm_traffic_manager_azure_endpoint" "secondary_endpoint" {
  name               = "secondary-endpoint"
  profile_id         = azurerm_traffic_manager_profile.traffic_profile.id
  priority           = 2
  weight             = 100
  target_resource_id = azurerm_app_service.app_balancer2.id
}
