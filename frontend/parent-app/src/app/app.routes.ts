import { Routes } from '@angular/router';
import { loadRemoteModule } from '@angular-architects/native-federation';
import { NotFoundComponent } from './not-found/not-found.component';
import { HomeComponent } from './home/home.component';

export const routes: Routes = [
  {
    path: '',
    component: HomeComponent,
    pathMatch: 'full',
  },
  {
    path: 'child1',
    loadComponent: () =>
      loadRemoteModule('child1', './Component').then((m) => m.AppComponent),
  },
  {
    path: 'child2',
    loadComponent: () =>
      loadRemoteModule('child2', './Component').then((m) => m.AppComponent),
  },
  {
    path: 'child3',
    loadComponent: () =>
      loadRemoteModule('child3', './Component').then((m) => m.AppComponent),
  },
  {
    path: '**',
    component: NotFoundComponent,
  },
];
