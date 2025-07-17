# plot_metrics.R - Compare metrics between MAS and BLE segmentations

library(ggplot2)
library(dplyr)
library(tidyr)
library(ggpubr)
library(cowplot)

output_dir <- "./results"

pd25_data <- read.csv("./results/PD25_metrics.csv")
preop_data <- read.csv("./results/preop_metrics.csv")

pd25_data$Source <- "PD25"
preop_data$Source <- "Preop"

# excluded subjects
exclude_subjects <- c("subj3", "subj8", "subj9", "subj19", "subj27", "subj29", "subj39", 
                   "subj43", "subj10", "subj13", "subj31", "subj47", "subj6")

# Filter out excluded subjects from both datasets
pd25_data <- pd25_data %>% filter(!Subject %in% exclude_subjects)
preop_data <- preop_data %>% filter(!Subject %in% exclude_subjects)

# Print subject count to assure correct number of subjects
cat("\nNumber of subjects after excluding", length(exclude_subjects), "patients:\n")
cat("PD25:", length(unique(pd25_data$Subject)), "\n")
cat("Preop:", length(unique(preop_data$Subject)), "\n")

# Combine datasets
all_data <- rbind(pd25_data, preop_data)

all_data$Side <- factor(all_data$Side)
all_data$Source <- factor(all_data$Source)

data_long <- all_data %>%
  pivot_longer(
    cols = c(Dice, Jaccard, Hausdorff, CentroidDistance),
    names_to = "Metric",
    values_to = "Value"
  )

# setup color scheme
box_colors <- c("PD25" = "#E69083", "Preop" = "#6A8EB7")  
point_colors <- c("PD25" = "#D16B5B", "Preop" = "#4A6B8A") 

# boxplot function
create_boxplot <- function(data, y_var, y_label, y_limits = NULL, title_text = NULL) {
  p <- ggplot(data, aes(x = Source, y = !!sym(y_var), fill = Source)) +
    geom_boxplot(alpha = 0.8, outlier.shape = NA, width = 0.6, linewidth = 1.2) +
    geom_jitter(aes(color = Source), width = 0.2, size = 1.5, alpha = 0.7) +
    scale_fill_manual(values = box_colors) +
    scale_color_manual(values = point_colors) +
    labs(y = y_label, title = title_text) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      axis.title.x = element_blank(),
      axis.title.y = element_text(size = 16, face = "bold"),  
      axis.text = element_text(size = 14, color = "black", face = "bold"),  
      axis.text.x = element_text(size = 16),  
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.background = element_rect(fill = "white", color = NA),
      legend.position = "none",
      plot.margin = margin(10, 20, 10, 20),  
      axis.line = element_line(color = "black", linewidth = 1.2),  
      axis.ticks = element_line(color = "black", linewidth = 1.0), 
      axis.ticks.length = unit(0.25, "cm"), 
      plot.title.position = "plot"
    )

  if (!is.null(y_limits)) {
    breaks <- seq(y_limits[1], y_limits[2], length.out = 5)
    p <- p + scale_y_continuous(limits = y_limits, breaks = breaks)
  }
  
  return(p)
}

dice_plot <- create_boxplot(
  filter(data_long, Metric == "Dice"), 
  "Value", 
  "Dice Coefficient",
  y_limits = c(0, 0.6),
  title_text = "Dice"
)

jaccard_plot <- create_boxplot(
  filter(data_long, Metric == "Jaccard"), 
  "Value", 
  "Jaccard Index",
  y_limits = c(0, 0.4),
  title_text = "Jaccard"
)

hausdorff_plot <- create_boxplot(
  filter(data_long, Metric == "Hausdorff"), 
  "Value", 
  "Hausdorff Distance (mm)",
  y_limits = c(0, 15),
  title_text = "Hausdorff"
)

centroid_plot <- create_boxplot(
  filter(data_long, Metric == "CentroidDistance"), 
  "Value", 
  "Centroid Distance (mm)",
  y_limits = c(0, 12),
  title_text = "CentroidDistance"
)

title <- ggdraw() + 
  draw_label(
    "Comparison of PD25 vs Preop STN Segmentations",
    fontface = "bold",
    size = 16,
    x = 0.5,
    y = 0.5
  )

plot_grid <- plot_grid(
  dice_plot, jaccard_plot, centroid_plot,
  ncol = 3, 
  align = "h",
  labels = NULL,
  rel_widths = c(1, 1, 1),  
  nrow = 1,        
  axis = "tb",     
  greedy = FALSE,  
  scale = 0.9     
)

plot_with_title <- plot_grid(
  title, plot_grid,
  ncol = 1,
  rel_heights = c(0.1, 1)
)


options(ragg.max_dim = 50000)  

ggsave(file.path(output_dir, "metrics_comparison_excluded.pdf"), 
       plot_with_title, 
       width = 16, 
       height = 5, 
       device = cairo_pdf,  
       dpi = 1800,        
       bg = "white")

#save as picture
ggsave(file.path(output_dir, "metrics_comparison_excluded.png"), 
       plot_with_title, 
       width = 16,  
       height = 5, 
       dpi = 1800,         
       bg = "white")

# Print statistical tests
cat("\nStatistical Tests (excluding", length(exclude_subjects), "patients):\n")
cat("================================================\n")

# statistical tests for all obtained metrices
for (metric in c("Dice", "Jaccard", "Hausdorff", "CentroidDistance")) {
  test_data <- filter(data_long, Metric == metric)
  test_result <- wilcox.test(Value ~ Source, data = test_data)
  cat("\n", metric, ":\n")
  cat("Wilcoxon test p-value:", format.pval(test_result$p.value, digits = 3), "\n")
}
