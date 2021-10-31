data "azurerm_container_registry" "jmeter_acr" {
  name                = var.JMETER_ACR_NAME
  resource_group_name = var.JMETER_ACR_RESOURCE_GROUP_NAME
}

data  "azurerm_resource_group" "jmeter_rg" {
  name     = var.RESOURCE_GROUP_NAME
}

 

data "azurerm_virtual_network" "jmeter_vnet" {
 name                = "${var.PREFIX}vnet"
   resource_group_name = var.RESOURCE_GROUP_NAME_VNET
}

data  "azurerm_subnet" "jmeter_subnet" {
 name                 = "${var.PREFIX}subnet"
 resource_group_name  = var.RESOURCE_GROUP_NAME_VNET
 virtual_network_name = "jmetervnet"
}

resource "random_id" "random" {
  byte_length = 4
}

#data   "azurerm_storage_account" "jmeter_storage" {
 # resource_group_name  = var.RESOURCE_GROUP_NAME                 
#  name = "jmeterstoraged9541e99"
 # location            = var.LOCATION
#}

#resource "azurerm_resource_group" "jmeter_rg" {
#  name     = var.RESOURCE_GROUP_NAME
#  location = var.LOCATION

#  tags = {
#    Application = var.JMETER_TAG_APPLICATION
#    Environment= var.JMETER_TAG_ENVIRONMENT
#  }
#}

#resource "azurerm_virtual_network" "jmeter_vnet" {
#  name                = "${var.PREFIX}vnet"
# location            = var.LOCATION
#  resource_group_name = var.RESOURCE_GROUP_NAME
#  address_space       = ["${var.VNET_ADDRESS_SPACE}"]
 #   tags = {
 #   Application = var.JMETER_TAG_APPLICATION
  #  Environment= var.JMETER_TAG_ENVIRONMENT
 # }
#}


#resource "azurerm_subnet" "jmeter_subnet" {
#  name                 = "${var.PREFIX}subnet"
  
#  resource_group_name  = var.RESOURCE_GROUP_NAME
#  virtual_network_name = "jmetervnet"
#  address_prefix       = var.SUBNET_ADDRESS_PREFIX

#  delegation {
#    name = "delegation"

 #   service_delegation {
 #     name    = "Microsoft.ContainerInstance/containerGroups"
 #     actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
#    }
 # }

 # service_endpoints = ["Microsoft.Storage"]
#}

resource "azurerm_network_profile" "jmeter_net_profile" {
  name                = "${var.PREFIX}netprofile"
  location            = var.LOCATION
  resource_group_name = var.RESOURCE_GROUP_NAME_VNET

  container_network_interface {
    name = "${var.PREFIX}cnic"

    ip_configuration {
      name      = "${var.PREFIX}ipconfig"
      subnet_id = data.azurerm_subnet.jmeter_subnet.id
    }
  }
}

resource "azurerm_storage_account" "jmeter_storage" {
  name                = "${var.PREFIX}storage${random_id.random.hex}"
  resource_group_name = var.RESOURCE_GROUP_NAME_VNET
  location            = var.LOCATION

  account_tier             = "Standard"
  account_replication_type = "LRS"

  network_rules {
    default_action             = "Allow"
    virtual_network_subnet_ids = ["${data.azurerm_subnet.jmeter_subnet.id}"]
  }
}

resource "azurerm_storage_share" "jmeter_share" {
  name                 = var.RESOURCE_GROUP_NAME_VNET
  storage_account_name = azurerm_storage_account.jmeter_storage.name
  quota                = var.JMETER_STORAGE_QUOTA_GIGABYTES
}


resource "azurerm_container_group" "jmeter_workers" {
  count               = var.JMETER_WORKERS_COUNT
  name                = "${var.PREFIX}-workerr${count.index}"
  resource_group_name = var.RESOURCE_GROUP_NAME
  location            = var.LOCATION

  ip_address_type = "private"
  os_type         = "Linux"

  network_profile_id = azurerm_network_profile.jmeter_net_profile.id

  image_registry_credential {
    server   = data.azurerm_container_registry.jmeter_acr.login_server
    username = data.azurerm_container_registry.jmeter_acr.admin_username
    password = data.azurerm_container_registry.jmeter_acr.admin_password
 }

  container {
    name   = "jmeter"
    image  = var.JMETER_DOCKER_IMAGE
    cpu    = var.JMETER_WORKER_CPU
    memory = var.JMETER_WORKER_MEMORY

    ports {
      port     = var.JMETER_DOCKER_PORT
      protocol = "TCP"
    }

    volume {
      name                 = "jmeter"
      mount_path           = "/jmeter"
      read_only            = true
      storage_account_name = azurerm_storage_account.jmeter_storage.name
      storage_account_key  = azurerm_storage_account.jmeter_storage.primary_access_key
      share_name           = azurerm_storage_share.jmeter_share.name
    }

    commands = [
      "/bin/sh",
      "-c",
      "cp -r /jmeter/* .; /entrypoint.sh -s -J server.rmi.ssl.disable=true",
    ]
  }
}
 
resource "azurerm_container_group" "jmeter_controller" {
  count = "${var.number_controller}"
  name                = "${var.PREFIX}-controller"
  resource_group_name = var.RESOURCE_GROUP_NAME
  location            = var.LOCATION


  ip_address_type = "private"
  os_type         = "Linux"

  network_profile_id = azurerm_network_profile.jmeter_net_profile.id

  restart_policy = "Never"

  image_registry_credential {
    server   = data.azurerm_container_registry.jmeter_acr.login_server
    username = data.azurerm_container_registry.jmeter_acr.admin_username
   password = data.azurerm_container_registry.jmeter_acr.admin_password
  }

  container {
    name   = "jmeter"
    image  = var.JMETER_DOCKER_IMAGE
    cpu    = var.JMETER_CONTROLLER_CPU
    memory = var.JMETER_CONTROLLER_MEMORY

    ports {
      port     = var.JMETER_DOCKER_PORT
      protocol = "TCP"
    }

    volume {
      name                 = "jmeter"
      mount_path           = "/jmeter"
      read_only            = false
      storage_account_name = azurerm_storage_account.jmeter_storage.name
      storage_account_key  = azurerm_storage_account.jmeter_storage.primary_access_key
      share_name           = azurerm_storage_share.jmeter_share.name
    }

    commands = [
      "/bin/sh",
      "-c",
   #   "cd /jmeter;/entrypoint.sh -n -J server.rmi.ssl.disable=true -t ${var.JMETER_JMX_FILE} -l ${var.JMETER_RESULTS_FILE} -e -o ${var.JMETER_DASHBOARD_FOLDER} -R ${join(",","${azurerm_container_group.jmeter_workers.*.ip_address}")} ${var.JMETER_EXTRA_CLI_ARGUMENTS}",
      "cd /jmeter;/entrypoint.sh -n -J server.rmi.ssl.disable=true -t ${var.JMETER_JMX_FILE} -l ${var.JMETER_RESULTS_FILE} -e -o ${var.JMETER_DASHBOARD_FOLDER} -R ${var.New_ip_list} ${var.JMETER_EXTRA_CLI_ARGUMENTS}",
    ]
  }
}
