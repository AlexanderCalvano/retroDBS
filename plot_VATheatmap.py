import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import matplotlib as mpl

# styling settings
plt.style.use('default')  
mpl.rcParams.update({
    'font.family': 'sans-serif',
    'font.sans-serif': ['Helvetica'],
    'font.size': 18,
    'axes.titlesize': 20,
    'axes.labelsize': 22,
    'xtick.labelsize': 18,
    'ytick.labelsize': 18,
    'figure.titlesize': 24,
    'text.color': 'black',
    'axes.labelcolor': 'black',
    'xtick.color': 'black',
    'ytick.color': 'black',
    'axes.linewidth': 1.2,  
    'axes.grid': False,
    'figure.facecolor': 'white',
    'axes.facecolor': 'white',
    'savefig.facecolor': 'white'
})

# Load and filter centroid data
df = pd.read_csv("/Users/alexandercalvano/Downloads/retroDBS/results/centroid_summary_all.csv")
excluded_outliers = ["subj3", "subj8", "subj9", "subj19", "subj27", "subj29", "subj39", 
                   "subj43", "subj10", "subj13", "subj31", "subj47", "subj6"]
df_vat_filtered = df[
    (df['Structure'] == 'VAT') &
    (~df['Subject'].isin(excluded_outliers))
]

fig, axes = plt.subplots(1, 2, figsize=(12, 6), constrained_layout=True)

kde_kwargs = dict(
    fill=True,
    alpha=0.9,  
    levels=180,
    thresh=0.3,
    bw_adjust=1.5
)

# KDE plots
# Left Hemisphere
sns.kdeplot(
    data=df_vat_filtered[df_vat_filtered['Side'] == 'left'],
    x="X", y="Y", cmap="Blues", ax=axes[0], **kde_kwargs
)
axes[0].set_title("Left Hemisphere")
axes[0].set_xlabel("MNI X")
axes[0].set_ylabel("MNI Y")

# Right Hemisphere
sns.kdeplot(
    data=df_vat_filtered[df_vat_filtered['Side'] == 'right'],
    x="X", y="Y", cmap="Blues", ax=axes[1], **kde_kwargs
)
axes[1].set_title("Right Hemisphere")
axes[1].set_xlabel("MNI X")
axes[1].set_ylabel("MNI Y")

xlims_left = (-18, -8)
xlims_right = (10, 20)
ylims = (-18, -6)

yticks = [-18, -15, -12, -9, -6]

xticks_left = [-18, -15.5, -13, -10.5, -8]
xticks_right = [10, 12.5, 15, 17.5, 20]

axes[0].set_yticks(yticks)
axes[1].set_yticks(yticks)
axes[0].set_xticks(xticks_left)
axes[1].set_xticks(xticks_right)

axes[0].set_xlim(xlims_left)
axes[1].set_xlim(xlims_right)
for ax in axes:
    ax.set_ylim(ylims)
    ax.set_facecolor('white')
    ax.grid(False)
    ax.set_aspect("equal")
    
    for spine in ax.spines.values():
        spine.set_visible(False)
    
    ax.spines['left'].set_visible(True)
    ax.spines['bottom'].set_visible(True)
    ax.spines['left'].set_linewidth(1.2)
    ax.spines['bottom'].set_linewidth(1.2)
    ax.spines['left'].set_color('black')
    ax.spines['bottom'].set_color('black')
    
    ax.spines['left'].set_position(('data', ax.get_xlim()[0]))
    ax.spines['bottom'].set_position(('data', ax.get_ylim()[0]))

    ax.tick_params(which='both', direction='out', length=6, width=1.2, colors='black')

axes[0].set_yticklabels(["" if y == -18 else str(y) for y in yticks])
axes[1].set_yticklabels(["" if y == -18 else str(y) for y in yticks])
axes[0].set_xticklabels([str(x) for x in xticks_left])
axes[1].set_xticklabels([str(x) for x in xticks_right])

fig.suptitle("VAT Centroid Distribution in MNI Space", fontsize=24, y=1.05)
plt.savefig('vat_heatmap.pdf', bbox_inches='tight', dpi=300, facecolor='white')
plt.show()