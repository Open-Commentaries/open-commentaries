import CETEI from 'CETEIcean';

const DRAG_ATTRIBUTE_NAME = 'phx-drop-target';
const DROP_TARGET_BG = 'bg-slate-50';

const teiTransformer = new CETEI();

export const DragHook = {
	isDropTarget(event) {
		const target = event.target;
		return target.getAttribute(DRAG_ATTRIBUTE_NAME) !== null;
	},

	mounted() {
		document.addEventListener('dragenter', event => {
			if (this.isDropTarget(event)) {
				event.target.classList.add(DROP_TARGET_BG);
			}
		});

		document.addEventListener('dragleave', event => {
			if (this.isDropTarget(event)) {
				event.target.classList.remove(DROP_TARGET_BG);
			}
		})
	}
};

export const DropboxChooserHook = {
	async mounted() {
		var button = Dropbox.createChooseButton(this.options());
		document.getElementById("dropbox-chooser-container").appendChild(button);
	},

	options() {
		return {
			success(files) {
				console.log(files);
			},
			linkType: 'direct',
			multiselect: false,
			extensions: ['.docx'],
		}
	}
}

export async function transformTei(raw) {
	if (!raw) {
		return Promise.resolve('');
	}

	return new Promise((resolve, _reject) =>
		teiTransformer.makeHTML5(raw, (data) => resolve(data))
	);
}

async function replaceRawTei(el) {
	const html = await transformTei(el.innerHTML);

	el.replaceChildren(html);
}

export const TEIHook = {
	async mounted() {
		return replaceRawTei(this.el);
	},

	async updated() {
		return replaceRawTei(this.el);
	}
}

export default {
	DragHook,
	DropboxChooserHook,
	TEIHook,
};
