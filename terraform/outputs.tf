output "k3s_nodes_details" {
  description = "Adresy IP wszystkich węzłów K3s"
  value       = { for k, v in module.k3s_nodes : k => v.ip_address[0] }
}